// =====================================================================
// display_controller.sv - Multiplexado de los displays de 7 segmentos
//
// Los cuatro digitos comparten fisicamente las siete lineas de segmento,
// asi que solo puede haber uno encendido en cada instante. El contador de
// digito avanza con cada tick de 1 ms y selecciona a la vez que nibble se
// decodifica y que anodo se activa.
//
//   AN0  unidades de victorias      AN2  unidades de segundos
//   AN1  decenas de victorias       AN3  decenas de segundos
//   AN4..AN7 permanecen apagados
//
// Frecuencia de barrido
// ---------------------
//   un digito por milisegundo, cuatro digitos -> 4 ms por ciclo completo
//   1 / 4 ms = 250 Hz
// El umbral de fusion de parpadeo del ojo esta alrededor de 60 Hz, asi
// que 250 Hz queda holgado. Reutilizar el tick de 1 ms evita anadir un
// contador dedicado.
//
// Conversion del tiempo a BCD
// ---------------------------
// El temporizador entrega segundos en binario y el decodificador necesita
// digitos decimales. La division entre diez tiene divisor constante y el
// rango esta acotado a 0..60, de modo que la sintesis la resuelve con una
// red pequena de LUTs y no con un divisor real. Si resultara costosa, la
// alternativa es que el temporizador cuente directamente en BCD.
//
// La tabla de segmentos se escribe con la convencion de que uno significa
// encendido, y la inversion se aplica al final con SEG_ACTIVE_LEVEL. Asi
// la tabla del codigo y la de la documentacion son la misma y no hay que
// razonar dos veces sobre la polaridad.
// =====================================================================

module display_controller #(
    parameter logic SEG_ACTIVE_LEVEL = 1'b0,   // 0 = segmento enciende con nivel bajo
    parameter logic AN_ACTIVE_LEVEL  = 1'b0    // 0 = digito habilita con nivel bajo
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       tick_i,       // pulso de 1 ms
    input  logic [6:0] time_s_i,     // segundos restantes, 0..60
    input  logic [7:0] wins_bcd_i,   // victorias en BCD, dos digitos
    output logic [6:0] seg_o,        // {g,f,e,d,c,b,a}
    output logic [7:0] an_o
);

    logic [1:0] dig_q = 2'd0;
    logic [3:0] t_dec, t_uni, nibble;
    logic [6:0] seg;
    logic [7:0] an;

    // ---- contador de digito ----
    always_ff @(posedge clk_i) begin
        if (rst_i)       dig_q <= 2'd0;
        else if (tick_i) dig_q <= dig_q + 2'd1;
    end

    // ---- conversion de segundos a dos digitos decimales ----
    // El cociente y el residuo se calculan con el ancho completo y se
    // rebanan de forma explicita. Evita el cast de una expresion variable,
    // que no todos los simuladores aceptan, y deja el truncamiento a la
    // vista en vez de implicito.
    logic [6:0] cociente;
    logic [3:0] residuo;

    assign cociente = time_s_i / 7'd10;

    // El residuo de dividir entre diez esta siempre entre 0 y 9, asi que
    // cabe en cuatro bits. El truncamiento es intencional y se declara
    // aqui en vez de arrastrar tres bits que nunca valen nada.
    /* verilator lint_off WIDTHTRUNC */
    assign residuo = time_s_i % 7'd10;
    /* verilator lint_on WIDTHTRUNC */

    // El temporizador nunca pasa de 60, pero la entrada admite hasta 127.
    // Un valor de dos digitos que no cabe se muestra apagado en lugar de
    // mostrar una cifra equivocada.
    assign t_dec = (cociente > 7'd9) ? 4'hF : cociente[3:0];
    assign t_uni = residuo;

    // ---- multiplexor de nibble ----
    // Los dos digitos del contador se separan con asignaciones continuas:
    // iverilog no admite selecciones constantes dentro de un always.
    logic [3:0] win_uni, win_dec;
    assign win_uni = wins_bcd_i[3:0];
    assign win_dec = wins_bcd_i[7:4];

    always_comb begin
        unique case (dig_q)
            2'd0:    nibble = win_uni;
            2'd1:    nibble = win_dec;
            2'd2:    nibble = t_uni;
            2'd3:    nibble = t_dec;
            default: nibble = 4'd0;
        endcase
    end

    // ---- decodificador BCD a siete segmentos ----
    //      seg = {g, f, e, d, c, b, a}, uno = encendido
    always_comb begin
        unique case (nibble)
            4'd0:    seg = 7'b0111111;
            4'd1:    seg = 7'b0000110;
            4'd2:    seg = 7'b1011011;
            4'd3:    seg = 7'b1001111;
            4'd4:    seg = 7'b1100110;
            4'd5:    seg = 7'b1101101;
            4'd6:    seg = 7'b1111101;
            4'd7:    seg = 7'b0000111;
            4'd8:    seg = 7'b1111111;
            4'd9:    seg = 7'b1101111;
            default: seg = 7'b0000000;   // fuera de rango: digito apagado
        endcase
    end

    // ---- decodificador de anodo, 2 a 8 ----
    // Escrito como tabla y no como an[dig_q]=1 para que el ancho del
    // indice no dependa del tamano del vector, y para que se lea como el
    // decodificador que es. AN4..AN7 nunca se activan.
    always_comb begin
        unique case (dig_q)
            2'd0:    an = 8'b0000_0001;
            2'd1:    an = 8'b0000_0010;
            2'd2:    an = 8'b0000_0100;
            2'd3:    an = 8'b0000_1000;
            default: an = 8'b0000_0000;
        endcase
    end

    // ---- aplicacion de polaridad ----
    assign seg_o = SEG_ACTIVE_LEVEL ? seg : ~seg;
    assign an_o  = AN_ACTIVE_LEVEL  ? an  : ~an;

endmodule
