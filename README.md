# Master-thesis
Master thesis at Elektroinstutionen Lund

## Info
The system is made to be run on a ChipWhisperer CW305 Artix-7 FPGA board. This can easily be changed to be used on other FPGAs by re-routing the pins described in wrapper/verilog/constraints.xdc.

This repo is not complete and will be updated when the different scripts have been cleaned up.
Things to look forward to:
- Implemented machine learning models
- Data generation scripts
- Data analysis scripts
- Figures
- Crypto attack script
- Finished paper
- Much more

### Acknowledgments
- Whole of HQC implementation found in wrapper/verilog/decaps was implemented by HQC team and can be found on [HQC website](https://pqc-hqc.org/resources.html)
- Implementation of UART (uart_rx.v and uart_tx.v), enabling the loader of ciphertext and secret keys, was done by Ben Marshall and can be found on [UART implementation](https://github.com/ben-marshall/uart/blob/master/rtl/uart_rx.v)
- Implementation of [OT-PCA data generator](https://github.com/ot-pca/ot-pca/), only small changes was made to make it compatible, such as fixing some pathing.

