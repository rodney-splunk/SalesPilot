End-to-end call test. Plays a real two-sided conversation through the SHIPPING app:

  rep voice      -> a player whose PID is excluded from the global system-audio tap
                    -> BlackHole 2ch, set as the default INPUT, so it reaches the microphone only.
  customer voice -> a separate, NOT-excluded player -> the real default OUTPUT, so the app's
                    system-audio tap captures it, exactly like the far end of a Webex call.

The tap is GLOBAL across output devices, so without that PID exclusion the rep's synthetic voice
would also land on the customer channel and the test would measure its own artifact. A process has
no CoreAudio process object until it has rendered audio, so the rep player is primed with a quiet
clip before the call starts, otherwise the exclusion silently does not bind.

Requires: BlackHole 2ch installed, Accessibility permission for the terminal, and the app built.
Restores the original default input/output devices on exit. Takes about two minutes and is audible.

  ./run.sh
