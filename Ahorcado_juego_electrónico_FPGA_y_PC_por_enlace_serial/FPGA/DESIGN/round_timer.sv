// =====================================================================
// round_timer.sv - Cuenta regresiva de la partida
//
// Dos contadores encadenados sobre el tick de 1 ms: uno acumula
// milisegundos hasta completar un segundo, el otro descuenta segundos.
//
// Separacion de load_i y run_i
// ---------------------------
// load_i carga el valor inicial y pone el acumulador de milisegundos a
// cero, para que el primer segundo dure un segundo completo. run_i
// habilita el descuento. Estan separados porque el control necesita
// detener el reloj al terminar la partida sin perder el valor mostrado:
// con una sola senal de arranque, el contador seguiria bajando durante
// la pantalla de resultado.
//
// timeout_o es un NIVEL, no un pulso
// ----------------------------------
// Se mantiene activo mientras la cuenta este en cero y el temporizador
// habilitado. Un pulso de un ciclo podria perderse: el control no
// siempre puede atender el vencimiento en el instante en que ocurre,
// porque puede estar a mitad de una pantalla del LCD o de una trama
// serial. Con un nivel, el aviso sigue ahi cuando el control queda libre.
//
// La cuenta se detiene en cero y no vuelve a dar la vuelta.
// =====================================================================

module round_timer #(
    parameter int TICKS_POR_SEGUNDO = 1000
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       tick_i,      // pulso de 1 ms
    input  logic       load_i,      // carga seconds_i y reinicia el acumulador
    input  logic [6:0] seconds_i,   // valor inicial en segundos
    input  logic       run_i,       // habilita el descuento
    output logic [6:0] time_s_o,    // segundos restantes
    output logic       timeout_o    // nivel: tiempo agotado
);

    localparam int W = (TICKS_POR_SEGUNDO <= 1) ? 1 : $clog2(TICKS_POR_SEGUNDO);

    logic [W-1:0] ms_q   = '0;
    logic [6:0]   secs_q = '0;

    assign time_s_o  = secs_q;
    assign timeout_o = run_i && (secs_q == 7'd0);

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            ms_q   <= '0;
            secs_q <= '0;
        end else if (load_i) begin
            ms_q   <= '0;
            secs_q <= seconds_i;
        end else if (run_i && tick_i) begin
            if (ms_q == W'(TICKS_POR_SEGUNDO - 1)) begin
                ms_q <= '0;
                if (secs_q != 7'd0) secs_q <= secs_q - 1'b1;
            end else begin
                ms_q <= ms_q + 1'b1;
            end
        end
    end

endmodule
