// =====================================================================
// uart_core_model.sv - Modelo de comportamiento del nucleo UART
//
// ESTE MODULO NO ES EL NUCLEO DEL PROYECTO.
//
// El nucleo TX/RX que el curso proporciona todavia no esta disponible.
// Para no quedarnos parados ni inventarnos su contenido, se escribe este
// modelo que cumple la interfaz minima declarada como supuesto y que
// permite verificar el periferico y el protocolo mientras tanto.
//
// Cuando llegue el nucleo real:
//   1. se sustituye este modelo por el nucleo en las simulaciones
//   2. se ejecuta la misma bateria de pruebas con ambos
//   3. se comparan los resultados
// Si difieren, lo que cambia es la capa de adaptacion del periferico, no
// los registros ni nada por encima.
//
// Trama: 1 bit de arranque, 8 de datos con el menos significativo
// primero, 1 bit de parada, sin paridad.
//
// La recepcion muestrea en el centro de cada bit: al detectar el flanco
// de bajada del arranque, el contador arranca a la mitad de un periodo,
// de modo que el primer vencimiento cae en el centro del bit de arranque
// y los siguientes en el centro de cada bit de datos. Muestrear en el
// centro y no en el borde da el maximo margen frente a diferencias de
// velocidad entre los dos extremos.
// =====================================================================

module uart_core_model #(
    parameter int BAUD_DIV = 868      // ciclos por bit
) (
    input  logic       clk_i,
    input  logic       rst_i,

    // linea serie
    output logic       tx_o,
    input  logic       rx_i,

    // frontera hacia el periferico
    input  logic [7:0] tx_data_i,
    input  logic       tx_start_i,
    output logic       tx_busy_o,
    output logic [7:0] rx_data_o,
    output logic       rx_valid_o
);

    localparam int W = (BAUD_DIV <= 1) ? 1 : $clog2(BAUD_DIV);

    // ---------------- transmision ----------------
    logic [9:0]   tx_shift_q = 10'h3FF;
    logic [3:0]   tx_bits_q  = 4'd0;
    logic [W-1:0] tx_div_q   = '0;
    logic         tx_busy_q  = 1'b0;

    assign tx_o      = tx_busy_q ? tx_shift_q[0] : 1'b1;
    assign tx_busy_o = tx_busy_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tx_shift_q <= 10'h3FF;
            tx_bits_q  <= 4'd0;
            tx_div_q   <= '0;
            tx_busy_q  <= 1'b0;
        end else if (!tx_busy_q) begin
            if (tx_start_i) begin
                // {parada, datos, arranque}, se emite desde el bit 0
                tx_shift_q <= {1'b1, tx_data_i, 1'b0};
                tx_bits_q  <= 4'd0;
                tx_div_q   <= '0;
                tx_busy_q  <= 1'b1;
            end
        end else begin
            if (tx_div_q == W'(BAUD_DIV - 1)) begin
                tx_div_q <= '0;
                if (tx_bits_q == 4'd9) begin
                    tx_busy_q <= 1'b0;
                end else begin
                    tx_shift_q <= {1'b1, tx_shift_q[9:1]};
                    tx_bits_q  <= tx_bits_q + 4'd1;
                end
            end else begin
                tx_div_q <= tx_div_q + 1'b1;
            end
        end
    end

    // ---------------- recepcion ----------------
    logic         rx_s1 = 1'b1, rx_s2 = 1'b1;
    logic         rx_busy_q  = 1'b0;
    logic [3:0]   rx_bits_q  = 4'd0;
    logic [W-1:0] rx_div_q   = '0;
    logic [7:0]   rx_shift_q = 8'h00;
    logic [7:0]   rx_data_q  = 8'h00;
    logic         rx_valid_q = 1'b0;

    assign rx_data_o  = rx_data_q;
    assign rx_valid_o = rx_valid_q;

    always_ff @(posedge clk_i) begin
        rx_s1 <= rx_i;
        rx_s2 <= rx_s1;
    end

    always_ff @(posedge clk_i) begin
        rx_valid_q <= 1'b0;

        if (rst_i) begin
            rx_busy_q  <= 1'b0;
            rx_bits_q  <= 4'd0;
            rx_div_q   <= '0;
            rx_shift_q <= 8'h00;
            rx_data_q  <= 8'h00;
        end else if (!rx_busy_q) begin
            if (!rx_s2) begin                     // flanco de arranque
                rx_busy_q <= 1'b1;
                rx_bits_q <= 4'd0;
                rx_div_q  <= W'(BAUD_DIV / 2);    // primer muestreo al centro
            end
        end else begin
            if (rx_div_q == W'(BAUD_DIV - 1)) begin
                rx_div_q <= '0;
                if (rx_bits_q == 4'd0) begin
                    // centro del bit de arranque: debe seguir bajo
                    if (rx_s2) rx_busy_q <= 1'b0; // ruido, se descarta
                    else       rx_bits_q <= 4'd1;
                end else if (rx_bits_q <= 4'd8) begin
                    rx_shift_q <= {rx_s2, rx_shift_q[7:1]};
                    rx_bits_q  <= rx_bits_q + 4'd1;
                end else begin
                    // centro del bit de parada
                    rx_busy_q <= 1'b0;
                    if (rx_s2) begin              // parada valida
                        rx_data_q  <= rx_shift_q;
                        rx_valid_q <= 1'b1;
                    end
                end
            end else begin
                rx_div_q <= rx_div_q + 1'b1;
            end
        end
    end

endmodule
