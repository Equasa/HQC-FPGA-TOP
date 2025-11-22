## Klocka från Husky HS2 (20-pin pin 6) -> fpga port clk_hs2
set_property PACKAGE_PIN N14 [get_ports clk_hs2];
set_property IOSTANDARD LVCMOS33 [get_ports clk_hs2];
create_clock -name hs2clk -period 20.0 [get_ports clk_hs2]; # 50 MHz

## UART: FPGA TX -> Husky RX på TIO1
set_property PACKAGE_PIN P16 [get_ports tio_tx]; # TIO1 (Husky serial_rx)
set_property IOSTANDARD LVCMOS33 [get_ports tio_tx];

## UART: FPGA TX -> Husky RX på TIO2
set_property PACKAGE_PIN R16 [get_ports tio_rx]; # TIO2 (Husky serial_tx)
set_property IOSTANDARD LVCMOS33 [get_ports tio_rx];

## Trigger: FPGA trig -> Husky TIO4
set_property PACKAGE_PIN T14 [get_ports trig];# TIO4
set_property IOSTANDARD LVCMOS33 [get_ports trig];
1