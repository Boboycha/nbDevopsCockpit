# Terminal display-scale smoke

Build the FMX project for the target platform. Set `SYNAPSE_ROOT` if Synapse
sources are outside the default `third_party/synapse` directory. On macOS run
as a high-resolution-capable app bundle and pass an absolute log-file path as
the first argument. The fixture moves only its own synthetic terminal window;
it opens no SSH connection, local shell or application profile.

With mixed-density displays connected, it traverses all displays forward and
back at control scales 100% and 125%. After painting settles, it checks the
renderer raster scale against the current window's native backing density
(NSWindow.backingScaleFactor on macOS) multiplied by the control transform.
The log includes canvas/raster/native/primary scales and the final failure
count. Exit code zero and `RESULT failures=0` indicate a pass.

The prior use of IFMXScreenService.GetScreenScale fails when the terminal is
on a display whose backing density differs from the primary display. A single
monitor or equal-density displays do not exercise that regression. Physical
text appearance still needs visual acceptance on the user's display.
