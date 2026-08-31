// =====================================================================
// lcd_screen_ctrl.sv - Capa de presentacion del LCD
//
// Convierte una orden de alto nivel, "dibuja esta pantalla", en las 34
// transacciones que hacen falta sobre el periferico: dos comandos de
// direccion y los 32 caracteres de las dos lineas.
//
// Por que existe este modulo
// --------------------------
// Si esta secuencia viviera dentro del control del juego, su maquina de
// estados pasaria de siete estados a varias decenas y mezclaria las
// reglas de la partida con el armado del texto. Aqui el control del juego
// solo dice que pantalla quiere y espera a que baje busy_o.
//
// Las lineas se escriben completas
// --------------------------------
// Siempre se emiten los 16 caracteres de cada linea, rellenando con
// espacios. Asi no quedan restos de la pantalla anterior y no hace falta
// limpiar antes de redibujar, que es justo lo que produce el parpadeo.
//
// Los datos se copian al empezar
// ------------------------------
// Al aceptar la orden se guarda una copia de la palabra, el patron, los
// errores, el modo y las victorias. El redibujado dura unos milisegundos;
// si se leyeran las entradas transaccion a transaccion, un cambio a mitad
// dejaria la parte de arriba de la pantalla con datos viejos y la de
// abajo con datos nuevos.
//
// Una orden que llega con busy_o en alto se ignora. Esperar es tarea de
// quien pide, igual que en el periferico.
//
// Dialogo con el periferico
// -------------------------
//   1. leer CONTROL hasta que busy este en cero
//   2. escribir el byte en DATOS
//   3. escribir CONTROL con rs y start
//   4. leer CONTROL hasta que done este en uno
//
// El paso 1 hace falta porque el periferico descarta lo que llegue
// ocupado, y al encender el LCD esta ocupado unos 50 ms con su propia
// secuencia de arranque. El paso 4 usa el flag de fin, que se queda
// puesto hasta que se acepta la operacion siguiente: por eso el sondeo no
// puede perderselo.
// =====================================================================

module lcd_screen_ctrl #(
    parameter int MAX_LEN = 12
) (
    input  logic        clk_i,
    input  logic        rst_i,

    // orden de dibujo
    input  logic [2:0]  screen_i,     // ver codigos mas abajo
    input  logic        redraw_i,     // pulso
    output logic        busy_o,

    // datos de la partida
    input  logic [8*MAX_LEN-1:0] word_data_i,   // primer caracter en los bits altos
    input  logic [3:0]           word_len_i,
    input  logic [MAX_LEN-1:0]   revealed_i,    // bit c en uno: posicion c revelada
    input  logic [2:0]           errors_i,      // errores cometidos, 0 a 6
    input  logic                 mode_i,        // 0 facil, 1 dificil
    input  logic [7:0]           wins_i,        // BCD de dos digitos

    // hacia lcd_peripheral
    output logic        write_enable_o,
    output logic [1:0]  addr_o,
    output logic [31:0] wdata_o,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] rdata_i       // solo se miran los bits de busy y done
    /* verilator lint_on UNUSEDSIGNAL */
);

    // codigos de pantalla
    localparam logic [2:0] SCR_SELECT      = 3'd0;
    localparam logic [2:0] SCR_PLAY        = 3'd1;
    localparam logic [2:0] SCR_WIN         = 3'd2;
    localparam logic [2:0] SCR_LOSE_FALLOS = 3'd3;
    localparam logic [2:0] SCR_LOSE_TIEMPO = 3'd4;

    // mapa de registros del periferico
    localparam logic [1:0] A_CTRL  = 2'b00;
    localparam logic [1:0] A_DATOS = 2'b01;
    localparam int         B_BUSY  = 8;
    localparam int         B_DONE  = 9;

    // Set DDRAM Address: fila 0 en 0x00 y fila 1 en 0x40, con el bit 7 que
    // identifica la instruccion.
    localparam logic [7:0] CMD_FILA0 = 8'h80;
    localparam logic [7:0] CMD_FILA1 = 8'hC0;

    localparam logic [7:0] CAR_ESPACIO = 8'h20;
    localparam logic [7:0] CAR_GUION   = 8'h5F;   // '_'
    localparam logic [7:0] CAR_CERO    = 8'h30;   // '0'
    localparam logic [7:0] CAR_D       = 8'h44;   // 'D' de dificil
    localparam logic [7:0] CAR_F       = 8'h46;   // 'F' de facil

    localparam int         N_COL    = 16;
    localparam int         N_PASOS  = 2 + 2*N_COL;   // dos comandos y 32 caracteres
    localparam logic [5:0] ULT_PASO = 6'(N_PASOS - 1);
    localparam logic [2:0] MAX_ERR  = 3'd6;

    // textos fijos, un caracter por columna, el primero en los bits altos
    localparam logic [8*N_COL-1:0] LIN_FACIL   = "MODO: FACIL     ";
    localparam logic [8*N_COL-1:0] LIN_DIFICIL = "MODO: DIFICIL   ";
    localparam logic [8*N_COL-1:0] LIN_GANASTE = "   GANASTE!     ";
    localparam logic [8*N_COL-1:0] LIN_FALLOS  = "PERDISTE: FALLOS";
    localparam logic [8*N_COL-1:0] LIN_TIEMPO  = "PERDISTE: TIEMPO";

    typedef enum logic [2:0] {
        S_IDLE,
        S_LIBRE,    // esperar a que el periferico quede libre
        S_DATOS,    // cargar el byte
        S_CTRL,     // pedir la transaccion
        S_FIN       // esperar el aviso de fin
    } estado_t;

    estado_t    st_q   = S_IDLE;
    logic [5:0] paso_q = 6'd0;

    // copia de los datos al aceptar la orden
    logic [2:0]           scr_q  = SCR_SELECT;
    logic [8*MAX_LEN-1:0] wd_q   = '0;
    logic [3:0]           wl_q   = 4'd0;
    logic [MAX_LEN-1:0]   rev_q  = '0;
    logic [2:0]           err_q  = 3'd0;
    logic                 mode_q = 1'b0;
    logic [7:0]           wins_q = 8'h00;

    assign busy_o = (st_q != S_IDLE);

    // ---------------------------------------------------------------
    // De que paso se trata
    // ---------------------------------------------------------------
    //   paso 0        comando de direccion de la fila 0
    //   paso 1..16    caracteres de la fila 0
    //   paso 17       comando de direccion de la fila 1
    //   paso 18..33   caracteres de la fila 1
    logic       es_comando, fila;
    logic [3:0] col;

    assign es_comando = (paso_q == 6'd0) || (paso_q == 6'd17);
    assign fila       = (paso_q >= 6'd17);

    // La columna es el numero de paso menos el del primer caracter de su
    // fila. La resta se hace en cuatro bits porque el resultado siempre
    // cae entre 0 y 15 y los bits altos no aportan nada.
    assign col = fila ? (paso_q[3:0] - 4'd2)     // paso 18 -> columna 0
                      : (paso_q[3:0] - 4'd1);    // paso  1 -> columna 0

    // ---------------------------------------------------------------
    // Lineas con contenido variable
    // ---------------------------------------------------------------
    logic [2:0] intentos;
    logic [4:0] wl5;

    assign intentos = MAX_ERR - err_q;    // hacia afuera se informa lo que queda
    assign wl5      = {1'b0, wl_q};

    logic [8*N_COL-1:0] lin_titulo, lin_modo, lin_intentos;

    assign lin_titulo = {"AHORCADO  V:",
                         CAR_CERO + {4'b0000, wins_q[7:4]},
                         CAR_CERO + {4'b0000, wins_q[3:0]},
                         "  "};

    assign lin_modo = mode_q ? LIN_DIFICIL : LIN_FACIL;

    assign lin_intentos = {"INTENTOS: ",
                           CAR_CERO + {5'b00000, intentos},
                           "    ",
                           mode_q ? CAR_D : CAR_F};

    // El patron y la palabra se arman columna a columna, asi que se
    // guardan como vector de caracteres y no como una linea de texto.
    logic [7:0] patron  [0:N_COL-1];
    logic [7:0] palabra [0:N_COL-1];

    always_comb begin
        for (int c = 0; c < N_COL; c++) begin
            patron[c]  = CAR_ESPACIO;
            palabra[c] = CAR_ESPACIO;
        end
        for (int c = 0; c < MAX_LEN; c++) begin
            if (c < wl5) begin
                palabra[c] = wd_q[8*(MAX_LEN-1-c) +: 8];
                patron[c]  = rev_q[c] ? wd_q[8*(MAX_LEN-1-c) +: 8] : CAR_GUION;
            end
        end
    end

    // ---------------------------------------------------------------
    // Caracter de la columna actual
    // ---------------------------------------------------------------
    logic [6:0] base;
    logic [7:0] car, byte_tx;
    logic       rs_tx;

    assign base = 7'd120 - {col, 3'b000};    // 8*(15 - col)

    always_comb begin
        unique case (scr_q)
            SCR_SELECT:      car = fila ? lin_modo[base +: 8] : lin_titulo[base +: 8];
            SCR_PLAY:        car = fila ? lin_intentos[base +: 8] : patron[col];
            SCR_WIN:         car = fila ? palabra[col] : LIN_GANASTE[base +: 8];
            SCR_LOSE_FALLOS: car = fila ? palabra[col] : LIN_FALLOS[base +: 8];
            SCR_LOSE_TIEMPO: car = fila ? palabra[col] : LIN_TIEMPO[base +: 8];
            default:         car = CAR_ESPACIO;
        endcase
    end

    assign byte_tx = es_comando ? (fila ? CMD_FILA1 : CMD_FILA0) : car;
    assign rs_tx   = !es_comando;

    // ---------------------------------------------------------------
    // Bus hacia el periferico
    // ---------------------------------------------------------------
    // Fuera de las dos escrituras la direccion se deja en CONTROL, que es
    // el registro que hay que sondear.
    always_comb begin
        write_enable_o = 1'b0;
        addr_o         = A_CTRL;
        wdata_o        = 32'd0;

        unique case (st_q)
            S_DATOS: begin
                write_enable_o = 1'b1;
                addr_o         = A_DATOS;
                wdata_o        = {24'd0, byte_tx};
            end
            S_CTRL: begin
                write_enable_o = 1'b1;
                wdata_o        = {30'd0, rs_tx, 1'b1};   // rs y start
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            st_q   <= S_IDLE;
            paso_q <= 6'd0;
        end else begin
            unique case (st_q)

                S_IDLE: begin
                    if (redraw_i) begin
                        scr_q  <= screen_i;
                        wd_q   <= word_data_i;
                        wl_q   <= word_len_i;
                        rev_q  <= revealed_i;
                        err_q  <= errors_i;
                        mode_q <= mode_i;
                        wins_q <= wins_i;
                        paso_q <= 6'd0;
                        st_q   <= S_LIBRE;
                    end
                end

                S_LIBRE: if (!rdata_i[B_BUSY]) st_q <= S_DATOS;

                S_DATOS: st_q <= S_CTRL;

                S_CTRL:  st_q <= S_FIN;

                S_FIN: begin
                    if (rdata_i[B_DONE]) begin
                        if (paso_q == ULT_PASO) begin
                            st_q <= S_IDLE;
                        end else begin
                            paso_q <= paso_q + 6'd1;
                            st_q   <= S_LIBRE;
                        end
                    end
                end

                default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
