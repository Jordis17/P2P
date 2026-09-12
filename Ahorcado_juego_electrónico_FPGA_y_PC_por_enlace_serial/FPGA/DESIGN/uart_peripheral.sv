// =====================================================================
// uart_peripheral.sv - Periferico UART con interfaz de registros
//
// Mapa de registros (interfaz estandar de 32 bits)
// ------------------------------------------------
//   addr 00  DATOS TX   bits [7:0] byte a transmitir
//   addr 01  DATOS RX   bits [7:0] ultimo byte recibido
//   addr 10  CONTROL    bit 0 send, bit 1 new_rx
//   addr 11  reservado, lee cero
//
// El registro CONTROL no es plano
// -------------------------------
// Hay que limpiar new_rx escribiendo el registro, pero una escritura de
// 32 bits toca send y new_rx a la vez. Con semantica plana, limpiar
// new_rx podria cancelar una transmision en curso, y lanzar una
// transmision podria borrar un new_rx recien llegado y perder la letra
// del jugador. Es una carrera real, y de las que se manifiestan como
// fallo intermitente justo el dia de la demostracion.
//
//   bit 0  send    escribir 1 arranca una transmision si no hay otra;
//                  escribir 0 no hace nada; se lee 1 mientras transmite
//                  y el hardware lo baja al terminar
//   bit 1  new_rx  escribir 1 limpia el aviso; escribir 0 no hace nada
//
// Asi los dos campos son independientes: ninguna escritura destruye el
// estado del otro.
//
// Prioridad en la recepcion
// -------------------------
// Si llega un byte en el mismo ciclo en que se limpia new_rx, gana la
// llegada: el aviso queda activo y el byte nuevo se conserva. Perder el
// byte seria peor que repetir el aviso.
//
// Capa de adaptacion al nucleo
// ----------------------------
// El nucleo UART del curso todavia no esta disponible, asi que este
// modulo se disena contra una interfaz minima declarada como supuesto:
//
//     tx_data_o, tx_start_o, tx_busy_i, rx_data_i, rx_valid_i
//
// Si el nucleo real resulta distinto, solo cambia esta frontera: los
// registros, la semantica de send y new_rx y todo lo que hay por encima
// quedan intactos.
//
// La maquina de transmision tiene un estado intermedio de arranque
// porque entre el pulso de inicio y el momento en que el nucleo levanta
// tx_busy puede pasar mas de un ciclo. Sin ese estado, send se bajaria
// de inmediato al ver tx_busy todavia en cero.
// =====================================================================

module uart_peripheral (
    input  logic        clk_i,
    input  logic        rst_i,

    // interfaz estandar de periferico
    input  logic        write_enable_i,
    input  logic [1:0]  addr_i,
    // Los bits 31:8 estan reservados por la interfaz estandar de 32 bits:
    // la carga util de este periferico es de un byte. Que no se usen es
    // deliberado, no un olvido.
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    // frontera con el nucleo UART
    output logic [7:0]  tx_data_o,
    output logic        tx_start_o,
    input  logic        tx_busy_i,
    input  logic [7:0]  rx_data_i,
    input  logic        rx_valid_i
);

    localparam logic [1:0] ADDR_TX   = 2'b00;
    localparam logic [1:0] ADDR_RX   = 2'b01;
    localparam logic [1:0] ADDR_CTRL = 2'b10;

    typedef enum logic [1:0] {
        TX_LIBRE,      // sin transmision
        TX_ARRANQUE,   // pulso enviado, esperando que el nucleo confirme
        TX_CURSO       // el nucleo esta transmitiendo
    } tx_estado_t;

    tx_estado_t tx_st_q = TX_LIBRE;

    logic [7:0] tx_reg_q  = 8'h00;
    logic [7:0] rx_reg_q  = 8'h00;
    logic       new_rx_q  = 1'b0;
    logic       tx_start_q = 1'b0;

    // ---- decodificacion de la escritura ----
    logic esc_tx, esc_ctrl, pide_send, pide_limpiar;
    assign esc_tx       = write_enable_i && (addr_i == ADDR_TX);
    assign esc_ctrl     = write_enable_i && (addr_i == ADDR_CTRL);
    assign pide_send    = esc_ctrl && wdata_i[0];
    assign pide_limpiar = esc_ctrl && wdata_i[1];

    // send se lee alto desde que se acepta hasta que el nucleo termina
    logic send_activo;
    assign send_activo = (tx_st_q != TX_LIBRE);

    // ---- lectura combinacional ----
    always_comb begin
        unique case (addr_i)
            ADDR_TX:   rdata_o = {24'd0, tx_reg_q};
            ADDR_RX:   rdata_o = {24'd0, rx_reg_q};
            ADDR_CTRL: rdata_o = {30'd0, new_rx_q, send_activo};
            default:   rdata_o = 32'd0;
        endcase
    end

    // ---- registro de transmision ----
    always_ff @(posedge clk_i) begin
        if (rst_i)        tx_reg_q <= 8'h00;
        else if (esc_tx)  tx_reg_q <= wdata_i[7:0];
    end

    // ---- maquina de transmision ----
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_st_q    <= TX_LIBRE;
            tx_start_q <= 1'b0;
        end else begin
            tx_start_q <= 1'b0;
            unique case (tx_st_q)
                TX_LIBRE:
                    if (pide_send) begin
                        tx_start_q <= 1'b1;      // pulso de un ciclo
                        tx_st_q    <= TX_ARRANQUE;
                    end
                TX_ARRANQUE:
                    if (tx_busy_i) tx_st_q <= TX_CURSO;
                TX_CURSO:
                    if (!tx_busy_i) tx_st_q <= TX_LIBRE;
                default:
                    tx_st_q <= TX_LIBRE;
            endcase
        end
    end

    // ---- recepcion ----
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rx_reg_q <= 8'h00;
            new_rx_q <= 1'b0;
        end else if (rx_valid_i) begin
            rx_reg_q <= rx_data_i;               // la llegada tiene prioridad
            new_rx_q <= 1'b1;
        end else if (pide_limpiar) begin
            new_rx_q <= 1'b0;
        end
    end

    assign tx_data_o  = tx_reg_q;
    assign tx_start_o = tx_start_q;

endmodule
