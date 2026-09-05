// =====================================================================
// uart_core_sim.sv - Nucleo UART para la regresion con iverilog
//
// ESTE NO ES EL NUCLEO DEL PROYECTO.
//
// El nucleo real es el que dio el curso en VHDL, y su envoltura esta en
// DESIGN/uart_core.sv. Pero iverilog no compila VHDL, asi que para poder
// correr la regresion completa hace falta un modulo que se llame igual y
// este escrito en SystemVerilog. Eso es este archivo: la misma interfaz,
// resuelta con el modelo de comportamiento.
//
// Los dos archivos declaran el modulo uart_core y por eso NUNCA se
// compilan juntos:
//
//   Vivado    DESIGN/*.sv + DESIGN/*.vhd            -> nucleo real
//   iverilog  DESIGN/*.sv menos uart_core.sv,
//             mas SIMULATION/uart_core_sim.sv       -> modelo
//
// De eso se encarga run_tests.py, que arma la lista de archivos.
//
// Lo que esta regresion comprueba es la logica del sistema, no el nucleo.
// El contraste contra el nucleo real se hace en Vivado con las mismas
// pruebas, que es donde se ve si la interfaz supuesta y la real coinciden.
// =====================================================================

// El nombre del modulo no coincide con el del archivo a proposito: son
// dos archivos que declaran uart_core y solo se distinguen por el nombre.
/* verilator lint_off DECLFILENAME */
module uart_core #(
    parameter int BAUD_DIV     = 868,
    /* verilator lint_off UNUSEDPARAM */
    parameter int BAUD_X16_DIV = 54     // el modelo no sobremuestrea
    /* verilator lint_on UNUSEDPARAM */
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
/* verilator lint_on DECLFILENAME */
