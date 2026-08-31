// =====================================================================
// clk_tick_gen.sv - Base de tiempo del sistema
//
// Genera un pulso de habilitacion de un ciclo cada TICK_CYCLES ciclos
// de reloj. Con el valor por defecto y un reloj de 100 MHz:
//
//     100 000 000 ciclos/s / 1000 ms/s = 100 000 ciclos por milisegundo
//
// El periodo resultante es exacto, sin error de redondeo, lo que importa
// porque de este tick dependen los 60 segundos de la partida.
//
// El tick es la salida directa del comparador y no se registra: un tick
// registrado llegaria un ciclo tarde y obligaria a compensar ese retardo
// en cada consumidor. Como solo se usa como habilitacion de logica
// sincrona, un glitch combinacional se estabiliza antes del flanco.
//
// El contador declara su valor inicial para que el sistema arranque en
// un estado conocido tras la configuracion de la FPGA, sin depender de
// un pulso de reset.
// =====================================================================

module clk_tick_gen #(
    parameter int TICK_CYCLES = 100_000
) (
    input  logic clk_i,
    input  logic rst_i,
    output logic tick_o
);

    // Ancho suficiente para contar hasta TICK_CYCLES-1.
    // El caso TICK_CYCLES <= 1 se acota para que el rango nunca sea nulo.
    localparam int W = (TICK_CYCLES <= 1) ? 1 : $clog2(TICK_CYCLES);

    logic [W-1:0] cnt_q = '0;

    assign tick_o = (cnt_q == W'(TICK_CYCLES - 1));

    always_ff @(posedge clk_i) begin
        if (rst_i)       cnt_q <= '0;
        else if (tick_o) cnt_q <= '0;
        else             cnt_q <= cnt_q + 1'b1;
    end

endmodule
