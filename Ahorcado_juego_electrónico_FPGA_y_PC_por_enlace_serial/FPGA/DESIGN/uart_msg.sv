// =====================================================================
// uart_msg.sv - Capa de presentacion del protocolo con la PC
//
// Traduce un evento del juego en las lineas ASCII que espera la
// aplicacion de PC y las entrega byte a byte al periferico UART, y en el
// sentido contrario recoge la letra que el jugador escribe.
//
// Mensajes
// --------
//   evento        lineas que emite
//   inicio        START:<M>:<LL>   PATT:<p>   ERR:<n>
//   letra         LET:<X>:<R>      PATT:<p>   ERR:<n>
//   repetida      LET:<X>:RPT
//   fin           END:<E>:<W>
//
//   <M>  F o D            <LL> longitud con dos digitos
//   <p>  patron, con guion bajo en lo oculto, tantos caracteres como
//        letras tenga la palabra
//   <X>  la letra         <R>  OK, NO o RPT, siempre tres caracteres
//   <n>  intentos que quedan
//   <E>  WIN, LER o LTO   <W>  la palabra completa
//
// Todas terminan en salto de linea. Los campos son de ancho fijo para
// que el analizador de Python trocee por posicion, sin expresiones
// regulares, y para que aqui solo el patron y la palabra tengan longitud
// variable.
//
// Por que existe este modulo
// --------------------------
// La secuencia mas larga son unos 35 bytes, cada uno con su escritura de
// registro y su espera. Metida en el control del juego, esa cuenta
// convertiria una maquina de siete estados en uno de esos bloques que
// nadie quiere leer ni defender.
//
// Los datos se copian al empezar
// ------------------------------
// Al aceptar el evento se guarda copia de la palabra, el patron, los
// errores, el modo, la letra y el resultado. Emitir la secuencia larga
// tarda unos 3 ms a 115200 baudios; leer las entradas byte a byte
// dejaria una trama con la letra de una jugada y el patron de la
// siguiente.
//
// Un evento que llega con busy_o en alto se ignora, igual que en las
// demas capas: esperar es tarea de quien pide.
//
// Dialogo con el periferico
// -------------------------
//   1. leer CONTROL hasta que send este en cero
//   2. escribir el byte en DATOS TX
//   3. escribir CONTROL con send
//   4. leer CONTROL hasta que send vuelva a cero
//
// El fin se detecta por send y no por ninguna otra senal. Con lazo de
// retorno, el receptor muestrea el bit de parada en su centro, medio bit
// antes de que el transmisor suelte la linea: cualquier aviso de
// recepcion llega antes de que la transmision haya terminado de verdad.
//
// Por que la recepcion tambien vive aqui
// --------------------------------------
// El periferico se maneja por registros, y limpiar el aviso de byte
// nuevo es una escritura mas sobre el mismo bus. Si el control del juego
// leyera por su cuenta habria dos maestros sobre el mismo periferico, con
// una trama saliendo y una letra entrando a la vez. Con la recepcion
// aqui se mantiene la regla de un solo maestro por periferico, la misma
// que se aplica al LCD.
//
// El sondeo del byte recibido ocurre solo en reposo, y una peticion de
// envio que caiga justo en esos dos ciclos queda anotada y se atiende al
// volver: lo que no se acepta es un envio con otro ya en curso.
//
// Validacion de la letra
// ----------------------
// Solo pasan los codigos de la A a la Z. Cualquier otra cosa se lee, se
// limpia el aviso y se descarta sin avisar a nadie: es filtrado de
// protocolo, no una regla del juego.
//
// rx_valid_o es un pulso de un ciclo. Si el control del juego no esta en
// disposicion de atenderlo, el byte se pierde, y eso es exactamente lo
// que se quiere fuera de la partida: una letra recibida en la pantalla
// de seleccion o mostrando el resultado se ignora, pero el aviso queda
// limpio y no se cuela como primera letra de la partida siguiente.
// =====================================================================

module uart_msg #(
    parameter int MAX_LEN = 12
) (
    input  logic        clk_i,
    input  logic        rst_i,

    // orden de envio
    input  logic [1:0]  event_i,      // ver codigos mas abajo
    input  logic        send_i,       // pulso
    output logic        busy_o,

    // letra recibida de la PC, ya validada
    output logic [7:0]  rx_letter_o,
    output logic        rx_valid_o,   // pulso de un ciclo

    // datos del evento
    input  logic [7:0]           letter_i,     // letra evaluada, en ASCII
    input  logic                 hit_i,        // 1 acierto, 0 fallo
    input  logic [1:0]           end_code_i,   // 0 WIN, 1 LER, 2 LTO
    input  logic [8*MAX_LEN-1:0] word_data_i,  // primer caracter en los bits altos
    input  logic [3:0]           word_len_i,
    input  logic [MAX_LEN-1:0]   revealed_i,
    input  logic [2:0]           errors_i,     // errores cometidos, 0 a 6
    input  logic                 mode_i,       // 0 facil, 1 dificil

    // hacia uart_peripheral
    output logic        write_enable_o,
    output logic [1:0]  addr_o,
    output logic [31:0] wdata_o,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] rdata_i       // solo se mira el bit de send
    /* verilator lint_on UNUSEDSIGNAL */
);

    // codigos de evento
    localparam logic [1:0] EV_INICIO   = 2'd0;
    localparam logic [1:0] EV_LETRA    = 2'd1;
    localparam logic [1:0] EV_REPETIDA = 2'd2;
    localparam logic [1:0] EV_FIN      = 2'd3;

    // mapa de registros del periferico
    localparam logic [1:0] A_TX     = 2'b00;
    localparam logic [1:0] A_RX     = 2'b01;
    localparam logic [1:0] A_CTRL   = 2'b10;
    localparam int         B_SEND   = 0;
    localparam int         B_NEW_RX = 1;

    localparam logic [7:0] CAR_A = 8'h41;
    localparam logic [7:0] CAR_Z = 8'h5A;

    localparam logic [7:0] CAR_LF      = 8'h0A;
    localparam logic [7:0] CAR_DOSP    = 8'h3A;   // ':'
    localparam logic [7:0] CAR_ESPACIO = 8'h20;
    localparam logic [7:0] CAR_GUION   = 8'h5F;   // '_'
    localparam logic [7:0] CAR_CERO    = 8'h30;
    localparam logic [7:0] CAR_UNO     = 8'h31;
    localparam logic [7:0] CAR_D       = 8'h44;
    localparam logic [7:0] CAR_F       = 8'h46;

    localparam int         N_POS   = 16;   // holgura sobre MAX_LEN para el indice
    localparam logic [2:0] MAX_ERR = 3'd6;

    // Prefijos rellenados a ocho caracteres para poder indexarlos todos
    // con el mismo calculo. Nunca se lee mas alla de los dos puntos.
    localparam logic [63:0] PRE_START = "START:  ";
    localparam logic [63:0] PRE_LET   = "LET:    ";
    localparam logic [63:0] PRE_PATT  = "PATT:   ";
    localparam logic [63:0] PRE_ERR   = "ERR:    ";
    localparam logic [63:0] PRE_END   = "END:    ";

    localparam logic [23:0] RES_OK  = "OK ";
    localparam logic [23:0] RES_NO  = "NO ";
    localparam logic [23:0] RES_RPT = "RPT";
    localparam logic [23:0] FIN_WIN = "WIN";
    localparam logic [23:0] FIN_LER = "LER";
    localparam logic [23:0] FIN_LTO = "LTO";

    // identificador de linea
    localparam logic [2:0] L_START = 3'd0;
    localparam logic [2:0] L_LET   = 3'd1;
    localparam logic [2:0] L_PATT  = 3'd2;
    localparam logic [2:0] L_ERR   = 3'd3;
    localparam logic [2:0] L_END   = 3'd4;

    typedef enum logic [2:0] {
        S_IDLE,
        S_LIBRE,       // esperar a que el transmisor quede libre
        S_DATOS,       // cargar el byte
        S_CTRL,        // pedir el envio
        S_FIN,         // esperar a que termine
        S_RX_LEER,     // leer el byte recibido
        S_RX_LIMPIAR   // limpiar el aviso de byte nuevo
    } estado_t;

    estado_t    st_q    = S_IDLE;
    logic [1:0] linea_q = 2'd0;    // linea dentro de la secuencia
    logic [4:0] idx_q   = 5'd0;    // byte dentro de la linea

    // copia de los datos al aceptar el evento
    logic [1:0]           ev_q   = EV_INICIO;
    logic [7:0]           let_q  = CAR_ESPACIO;
    logic                 hit_q  = 1'b0;
    logic [1:0]           fin_q  = 2'd0;
    logic [8*MAX_LEN-1:0] wd_q   = '0;
    logic [3:0]           wl_q   = 4'd0;
    logic [MAX_LEN-1:0]   rev_q  = '0;
    logic [2:0]           err_q  = 3'd0;
    logic                 mode_q = 1'b0;

    logic pend_q = 1'b0;    // envio anotado y todavia no empezado
    logic rx_val_q = 1'b0;
    logic [7:0] rx_byte_q = 8'h00;

    assign rx_letter_o = rx_byte_q;
    assign rx_valid_o  = rx_val_q;

    // Una transmision en curso ocupa los cuatro estados del dialogo. El
    // sondeo de recepcion no cuenta como ocupado: dura dos ciclos y no
    // impide anotar un envio.
    logic tx_en_curso;
    assign tx_en_curso = (st_q == S_LIBRE) || (st_q == S_DATOS) ||
                         (st_q == S_CTRL)  || (st_q == S_FIN);
    assign busy_o      = tx_en_curso || pend_q;

    // ---------------------------------------------------------------
    // Que linea toca
    // ---------------------------------------------------------------
    logic [2:0] linea_id;
    logic [1:0] n_lineas;

    assign n_lineas = ((ev_q == EV_INICIO) || (ev_q == EV_LETRA)) ? 2'd3 : 2'd1;

    always_comb begin
        unique case (ev_q)
            EV_INICIO: begin
                if      (linea_q == 2'd0) linea_id = L_START;
                else if (linea_q == 2'd1) linea_id = L_PATT;
                else                      linea_id = L_ERR;
            end
            EV_LETRA: begin
                if      (linea_q == 2'd0) linea_id = L_LET;
                else if (linea_q == 2'd1) linea_id = L_PATT;
                else                      linea_id = L_ERR;
            end
            EV_REPETIDA: linea_id = L_LET;
            EV_FIN:      linea_id = L_END;
            default:     linea_id = L_END;
        endcase
    end

    // longitud de la linea actual
    logic [4:0] len_linea, ult_idx;
    always_comb begin
        unique case (linea_id)
            L_START: len_linea = 5'd11;                  // START:M:LL y salto
            L_LET:   len_linea = 5'd10;                  // LET:X:RRR y salto
            L_PATT:  len_linea = 5'd6 + {1'b0, wl_q};    // PATT: patron y salto
            L_ERR:   len_linea = 5'd6;                   // ERR:n y salto
            default: len_linea = 5'd9 + {1'b0, wl_q};    // END:EEE:palabra y salto
        endcase
    end
    assign ult_idx = len_linea - 5'd1;

    // ---------------------------------------------------------------
    // Campos variables
    // ---------------------------------------------------------------
    logic [7:0] len_dec, len_uni, dig_intentos;
    logic [2:0] intentos;

    // La longitud nunca pasa de doce, asi que el digito de las decenas
    // sale de una comparacion y no de una division.
    assign len_dec      = (wl_q >= 4'd10) ? CAR_UNO : CAR_CERO;
    assign len_uni      = CAR_CERO + ((wl_q >= 4'd10) ? {4'd0, wl_q - 4'd10}
                                                      : {4'd0, wl_q});
    assign intentos     = MAX_ERR - err_q;
    assign dig_intentos = CAR_CERO + {5'b00000, intentos};

    logic [23:0] res3, fin3;
    assign res3 = (ev_q == EV_REPETIDA) ? RES_RPT : (hit_q ? RES_OK : RES_NO);

    always_comb begin
        unique case (fin_q)
            2'd0:    fin3 = FIN_WIN;
            2'd1:    fin3 = FIN_LER;
            2'd2:    fin3 = FIN_LTO;
            default: fin3 = FIN_LTO;
        endcase
    end

    // patron y palabra, un caracter por posicion
    logic [7:0] patron  [0:N_POS-1];
    logic [7:0] palabra [0:N_POS-1];

    always_comb begin
        for (int c = 0; c < N_POS; c++) begin
            patron[c]  = CAR_ESPACIO;
            palabra[c] = CAR_ESPACIO;
        end
        for (int c = 0; c < MAX_LEN; c++) begin
            palabra[c] = wd_q[8*(MAX_LEN-1-c) +: 8];
            patron[c]  = rev_q[c] ? wd_q[8*(MAX_LEN-1-c) +: 8] : CAR_GUION;
        end
    end

    // ---------------------------------------------------------------
    // Byte que toca emitir
    // ---------------------------------------------------------------
    logic [63:0] pre;
    always_comb begin
        unique case (linea_id)
            L_START: pre = PRE_START;
            L_LET:   pre = PRE_LET;
            L_PATT:  pre = PRE_PATT;
            L_ERR:   pre = PRE_ERR;
            default: pre = PRE_END;
        endcase
    end

    logic [5:0] base_pre;
    logic [7:0] car_pre;
    assign base_pre = 6'd56 - {idx_q[2:0], 3'b000};   // 8*(7 - idx)
    assign car_pre  = pre[base_pre +: 8];

    // Las posiciones dentro del patron y de la palabra se cuentan desde
    // donde empieza cada campo. La resta va en cuatro bits porque el
    // resultado siempre cae por debajo de la longitud maxima.
    logic [3:0] pos_patt, pos_word;

    assign pos_patt = idx_q[3:0] - 4'd5;
    assign pos_word = idx_q[3:0] - 4'd8;

    // Los tres caracteres de cada campo fijo se separan aqui y no dentro
    // del bloque combinacional: iverilog no admite selecciones constantes
    // en procesos always y avisa de que incluira el vector entero.
    logic [7:0] res_c0, res_c1, res_c2, fin_c0, fin_c1, fin_c2;
    assign res_c0 = res3[23:16];
    assign res_c1 = res3[15:8];
    assign res_c2 = res3[7:0];
    assign fin_c0 = fin3[23:16];
    assign fin_c1 = fin3[15:8];
    assign fin_c2 = fin3[7:0];

    logic [7:0] car;
    always_comb begin
        car = CAR_LF;
        unique case (linea_id)

            // START:<M>:<LL>
            L_START: begin
                if      (idx_q <  5'd6) car = car_pre;
                else if (idx_q == 5'd6) car = mode_q ? CAR_D : CAR_F;
                else if (idx_q == 5'd7) car = CAR_DOSP;
                else if (idx_q == 5'd8) car = len_dec;
                else if (idx_q == 5'd9) car = len_uni;
                else                    car = CAR_LF;
            end

            // LET:<X>:<R>
            L_LET: begin
                if      (idx_q <  5'd4) car = car_pre;
                else if (idx_q == 5'd4) car = let_q;
                else if (idx_q == 5'd5) car = CAR_DOSP;
                else if (idx_q == 5'd6) car = res_c0;
                else if (idx_q == 5'd7) car = res_c1;
                else if (idx_q == 5'd8) car = res_c2;
                else                    car = CAR_LF;
            end

            // PATT:<p>
            L_PATT: begin
                if      (idx_q < 5'd5)  car = car_pre;
                else if (idx_q < len_linea - 5'd1) car = patron[pos_patt];
                else                    car = CAR_LF;
            end

            // ERR:<n>
            L_ERR: begin
                if      (idx_q <  5'd4) car = car_pre;
                else if (idx_q == 5'd4) car = dig_intentos;
                else                    car = CAR_LF;
            end

            // END:<E>:<W>
            default: begin
                if      (idx_q <  5'd4) car = car_pre;
                else if (idx_q == 5'd4) car = fin_c0;
                else if (idx_q == 5'd5) car = fin_c1;
                else if (idx_q == 5'd6) car = fin_c2;
                else if (idx_q == 5'd7) car = CAR_DOSP;
                else if (idx_q < len_linea - 5'd1) car = palabra[pos_word];
                else                    car = CAR_LF;
            end
        endcase
    end

    // ---------------------------------------------------------------
    // Bus hacia el periferico
    // ---------------------------------------------------------------
    // Fuera de las escrituras la direccion se deja en CONTROL, que es el
    // registro que hay que sondear.
    always_comb begin
        write_enable_o = 1'b0;
        addr_o         = A_CTRL;
        wdata_o        = 32'd0;

        unique case (st_q)
            S_DATOS: begin
                write_enable_o = 1'b1;
                addr_o         = A_TX;
                wdata_o        = {24'd0, car};
            end
            S_CTRL: begin
                write_enable_o = 1'b1;
                wdata_o        = 32'd1;      // solo send; new_rx no se toca
            end
            S_RX_LEER: addr_o = A_RX;
            S_RX_LIMPIAR: begin
                write_enable_o = 1'b1;
                wdata_o        = 32'd2;      // solo new_rx; send no se toca
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk_i) begin
        rx_val_q <= 1'b0;

        if (rst_i) begin
            st_q     <= S_IDLE;
            linea_q  <= 2'd0;
            idx_q    <= 5'd0;
            pend_q   <= 1'b0;
            rx_byte_q <= 8'h00;
        end else begin
            // La orden se anota y los datos se copian en el mismo ciclo en
            // que llega, aunque el sondeo de recepcion este a mitad. Solo
            // se descarta si ya hay una transmision en curso.
            if (send_i && !tx_en_curso && !pend_q) begin
                pend_q <= 1'b1;
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

            unique case (st_q)

                S_IDLE: begin
                    if (pend_q) begin
                        pend_q  <= 1'b0;
                        linea_q <= 2'd0;
                        idx_q   <= 5'd0;
                        st_q    <= S_LIBRE;
                    end else if (rdata_i[B_NEW_RX]) begin
                        st_q <= S_RX_LEER;
                    end
                end

                S_RX_LEER: begin
                    rx_byte_q <= rdata_i[7:0];
                    st_q      <= S_RX_LIMPIAR;
                end

                S_RX_LIMPIAR: begin
                    // el aviso se limpia siempre; el pulso solo sale si el
                    // byte es una letra
                    if ((rx_byte_q >= CAR_A) && (rx_byte_q <= CAR_Z)) begin
                        rx_val_q <= 1'b1;
                    end
                    st_q <= S_IDLE;
                end

                S_LIBRE: if (!rdata_i[B_SEND]) st_q <= S_DATOS;

                S_DATOS: st_q <= S_CTRL;

                S_CTRL:  st_q <= S_FIN;

                S_FIN: begin
                    if (!rdata_i[B_SEND]) begin
                        if (idx_q != ult_idx) begin
                            idx_q <= idx_q + 5'd1;
                            st_q  <= S_LIBRE;
                        end else if (linea_q != n_lineas - 2'd1) begin
                            linea_q <= linea_q + 2'd1;
                            idx_q   <= 5'd0;
                            st_q    <= S_LIBRE;
                        end else begin
                            st_q <= S_IDLE;
                        end
                    end
                end

                default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
