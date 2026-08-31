// =====================================================================
// uart_core.sv - RELLENO PROVISIONAL, NO ES EL NUCLEO DEL PROYECTO
//
// El nucleo TX/RX que proporciona el curso todavia no esta disponible.
// El top lo instancia con el nombre uart_core y la interfaz declarada
// como supuesto en el documento de diseno:
//
//     tx_data_i, tx_start_i, tx_busy_o, rx_data_o, rx_valid_o
//
// Este archivo solo existe para que el sistema completo se pueda
// elaborar y simular mientras tanto: se limita a envolver el modelo de
// comportamiento uart_core_model.
//
// Cuando llegue el nucleo real:
//   1. se anade su archivo a DESIGN
//   2. se borra este de SIMULATION
//   3. se repiten las mismas pruebas y se comparan los resultados
// Si la interfaz del nucleo real no coincide con el supuesto, lo unico
// que cambia es la capa de adaptacion de uart_peripheral.
//
// Este archivo NO debe entrar en el proyecto de Vivado como fuente de
// sintesis.
// =====================================================================

module uart_core #(
    parameter int BAUD_DIV = 868
) (
    input  logic       clk_i,
    input  logic       rst_i,
    output logic       tx_o,
    input  logic       rx_i,
    input  logic [7:0] tx_data_i,
    input  logic       tx_start_i,
    output logic       tx_busy_o,
    output logic [7:0] rx_data_o,
    output logic       rx_valid_o
);

    uart_core_model #(.BAUD_DIV(BAUD_DIV)) modelo (
        .clk_i(clk_i), .rst_i(rst_i),
        .tx_o(tx_o), .rx_i(rx_i),
        .tx_data_i(tx_data_i), .tx_start_i(tx_start_i), .tx_busy_o(tx_busy_o),
        .rx_data_o(rx_data_o), .rx_valid_o(rx_valid_o)
    );

endmodule
