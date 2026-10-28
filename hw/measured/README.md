# Board measurements

| File | Content | Nature |
|---|---|---|
| `flash_jtag.txt` | three-step JTAG chain and GPIO readback | JTAG path evidence |
| `health.txt` | serial, JTAG and exception-vector snapshot | current evidence |
| `qspi_program.txt` | QSPI erase, program and verify | current evidence |
| `telemetry_8s.txt` | 1 Hz telemetry during an 8-second stream | current evidence |
| `link_selftest.txt` | clean to loss to recovery self-test | current evidence |
| `uart_battery.txt` | serial command battery | current evidence |
| `sd_playback.txt` | SD resume after selecting a clip | supporting; the link change does not touch SD |
| `pane_integrity.txt` | 185 degree processed-pane integrity | supporting; display-side evidence from the same RTL |
| `link_gap.txt` | frame-gap statistics after a cold boot | current evidence |
| `cold_boot.txt` | QSPI cold boot after a power cycle | current evidence |
| `uart_battery_capture.txt` | raw serial capture of the 105 commands | raw capture |
