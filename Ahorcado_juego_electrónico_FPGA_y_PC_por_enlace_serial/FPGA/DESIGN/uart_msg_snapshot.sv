// =====================================================================
// uart_msg_snapshot.sv - Copia estable de los datos del evento
//
// Guarda los datos de la jugada en el momento en que se acepta la orden
// de envio, y los mantiene quietos hasta la siguiente.
//
// Hace falta porque emitir la secuencia larga tarda unos 3 ms a 115200
// baudios, y en ese rato el control del juego puede recibir otra letra y
// cambiar sus salidas. Si el generador de caracteres leyera las entradas
// directamente, saldria una trama con la letra de una jugada y el patron
// de la siguiente.
//
// Los registros no llevan reinicio. Solo se escriben cuando llega el
// pulso de captura, y hasta que eso pase no hay ninguna trama que
// dependa de su contenido. Sus valores iniciales quedan grabados en el
// bitstream, igual que en el resto del proyecto.
// =====================================================================

module uart_msg_snapshot #(
    parameter int MAX_LEN = 12
) (
    input  logic clk_i,
    input  logic capture_i,                     // pulso: copiar las entradas

    // datos tal como los publica el control del juego
    input  logic [1:0]           event_i,
    input  logic [7:0]           letter_i,
    input  logic                 hit_i,
    input  logic [1:0]           end_code_i,
    input  logic [8*MAX_LEN-1:0] word_data_i,
    input  logic [3:0]           word_len_i,
    input  logic [MAX_LEN-1:0]   revealed_i,
    input  logic [2:0]           errors_i,
    input  logic                 mode_i,

    // los mismos datos, ya congelados
    output logic [1:0]           event_o,
    output logic [7:0]           letter_o,
    output logic                 hit_o,
    output logic [1:0]           end_code_o,
    output logic [8*MAX_LEN-1:0] word_data_o,
    output logic [3:0]           word_len_o,
    output logic [MAX_LEN-1:0]   revealed_o,
    output logic [2:0]           errors_o,
    output logic                 mode_o
);

    localparam logic [7:0] CAR_ESPACIO = 8'h20;

    logic [1:0]           ev_q   = 2'd0;
    logic [7:0]           let_q  = CAR_ESPACIO;
    logic                 hit_q  = 1'b0;
    logic [1:0]           fin_q  = 2'd0;
    logic [8*MAX_LEN-1:0] wd_q   = '0;
    logic [3:0]           wl_q   = 4'd0;
    logic [MAX_LEN-1:0]   rev_q  = '0;
    logic [2:0]           err_q  = 3'd0;
    logic                 mode_q = 1'b0;

    always_ff @(posedge clk_i) begin
        if (capture_i) begin
            ev_q   <= event_i;
            let_q  <= letter_i;
            hit_q  <= hit_i;
            fin_q  <= end_code_i;
            wd_q   <= word_data_i;
            wl_q   <= word_len_i;
            rev_q  <= revealed_i;
            err_q  <= errors_i;
            mode_q <= mode_i;
        end
    end

    assign event_o     = ev_q;
    assign letter_o    = let_q;
    assign hit_o       = hit_q;
    assign end_code_o  = fin_q;
    assign word_data_o = wd_q;
    assign word_len_o  = wl_q;
    assign revealed_o  = rev_q;
    assign errors_o    = err_q;
    assign mode_o      = mode_q;

endmodule
