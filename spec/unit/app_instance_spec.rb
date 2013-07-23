require 'spec_helper'

module HealthManager
  describe AppInstance do
    subject(:instance) { AppInstance.new("version", 0, 'fuid') }
    let(:heartbeat) { Heartbeat.new({'instance' => 'fuid', 'state' => 'RUNNING', 'version' => "version", 'index' => 0}) }

    before do
      Config.load({})
    end

    describe "checked_in_recently?" do
      context "when no heartbeats have been received" do
        it { should_not have_recent_heartbeat }
      end

      context "when a heartbeat was received recently" do
        before do
          instance.receive_heartbeat(heartbeat)
        end

        it { should have_recent_heartbeat }
      end

      context "when a heartbeat was received a while back" do
        before do
          Timecop.freeze(Time.now - Config.interval(:droplet_lost) - 1) do
            instance.receive_heartbeat(heartbeat)
          end
        end

        it { should_not have_recent_heartbeat }
      end
    end

    describe "alive?" do
      context "when crashed" do
        before do
          instance.receive_heartbeat(heartbeat)
          instance.crash!(0)
        end
        it { should_not be_alive }
      end

      context "when there is no hearbeat" do
        it { should_not be_alive }
      end

      context "when the last heartbeat was received too long ago" do
        before do
          Timecop.freeze(Time.now - Config.interval(:droplet_lost) - 1) do
            instance.receive_heartbeat(heartbeat)
          end
        end

        it { should_not be_alive }
      end

      context "when the instance has not crashed, and has a recent enough heartbeat" do
        before do
          Timecop.freeze(Time.now - Config.interval(:droplet_lost) + 1) do
            instance.receive_heartbeat(heartbeat)
          end
        end

        it { should be_alive }
      end
    end

    describe "determining when an instance is flapping" do
      context "first crash" do
        before do
          instance.crash!(0)
        end

        it "should be crashed, and not flapping" do
          expect(instance).to be_crashed
        end

        context "when enough crashes arrive before the flapping interval" do
          before do
            timeout = Config.interval(:flapping_timeout)
            (1..Config.interval(:flapping_death)).each do |crash_count|
              instance.crash!(timeout - 1)
            end
          end

          it "should be flapping" do
            expect(instance).to be_flapping
          end
        end

        context "when more crashes arrive, but after the flapping interval" do
          before do
            timeout = Config.interval(:flapping_timeout)
            (1...Config.interval(:flapping_death)).each do |crash_count|
              instance.crash!(timeout - 1)
            end
            instance.crash!(timeout + 1)
          end

          it "should be crashed" do
            expect(instance).to be_crashed
          end
        end
      end
    end

    describe "pending restarts" do
      context "when marked for pending restart" do
        before do
          instance.mark_pending_restart_with_receipt!("foo")
        end

        it "should be pending a restart and should return the passed in receipt" do
          expect(instance).to be_pending_restart
          expect(instance.pending_restart_receipt).to eq("foo")
        end

        context "when unmarked" do
          before do
            instance.unmark_pending_restart!
          end

          it "should lose the receipt and not be pending restart" do
            expect(instance.pending_restart_receipt).to be_nil
            expect(instance).not_to be_pending_restart
          end
        end
      end
    end

    describe "giveup_restarting?" do
      before do
        Config.stub(:interval).and_call_original
        Config.stub(:interval).with(:giveup_crash_number).and_return(configured_giveup)
      end

      context "when configured to never give up" do
        let(:configured_giveup) { 0 }

        it 'should never give up' do
          10.times do |i|
            instance.crash!(i)
          end
          instance.should_not be_giveup_restarting
        end
      end

      context "when configured to giveup at some point" do
        let(:configured_giveup) { 4 }

        it 'should not give up until after reaching that point' do
          configured_giveup.times do |i|
            instance.crash!(i)
          end
          instance.should_not be_giveup_restarting
          instance.crash!(configured_giveup + 1)
          instance.should be_giveup_restarting
        end
      end
    end
  end
end