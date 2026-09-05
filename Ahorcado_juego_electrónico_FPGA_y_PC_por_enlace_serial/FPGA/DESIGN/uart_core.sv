// =====================================================================
// uart_core.sv - Envoltura del nucleo UART en VHDL
//
// El nucleo lo proporciono el curso en VHDL (UART_tx.vhd y UART_rx.vhd,
// sin modificar). Este modulo lo adapta a la interfaz que el periferico
// espera. Es la capa de adaptacion que el documento de diseno anuncio:
// todo lo que dependia del nucleo real queda aqui, y ni los registros ni
// nada por encima cambian.
//
// Este archivo NO se puede compilar con iverilog ni revisar con
// verilator: instancia entidades VHDL. La simulacion mixta se hace en
// Vivado. Para la regresion con iverilog esta uart_core_sim.sv, que
// declara el mismo modulo sobre el modelo de comportamiento.
//
// No se usa UART.vhd
// ------------------
// Ese archivo solo cablea el transmisor con el receptor, pero no expone
// los genericos de la velocidad, asi que sus componentes se quedarian
// con los valores por omision, calculados para un reloj de 16 MHz. Se
// instancian las dos entidades directamente para poder pasarles los
// valores de 100 MHz. El archivo se conserva en el repositorio tal como
// llego, sin tocar, aunque no se instancie.
//
// Velocidad a 100 MHz
// -------------------
//   transmision: ciclos por bit = 100e6 / 115200 = 868.06 -> 868
//                error -0.006 %
//
//   recepcion:   el receptor sobremuestrea por 16, asi que su generico
//                es (100e6 / 115200) / 16 = 54.25 -> 54
//                bit real 16 x 54 = 864 ciclos, error -0.47 %
//
// Ese -0.47 % se acumula a lo largo de la trama. El receptor muestrea el
// bit k a 1.5 + k tiempos de bit del flanco de arranque, asi que en el
// bit 8, el ultimo, el desfase es de 3.97 % de un bit. Sumando los 0.54
// us de latencia con que puede detectarse el flanco de arranque, que son
// otro 6.22 %, el peor caso queda en 10.2 % de un bit frente al 50 % que
// habria disponible hasta el borde. Hay margen de sobra.
//
// tx_rdy no es una senal de listo
// -------------------------------
// A pesar del nombre, tx_rdy es un pulso de un ciclo al terminar cada
// byte, no un nivel que diga si el transmisor esta libre. El periferico
// necesita un nivel de ocupado, y de eso se encarga esta envoltura.
//
// La peticion se mantiene, no se pulsa
// ------------------------------------
// El nucleo ignora tx_start durante casi todo un tiempo de bit despues
// de terminar un byte, mientras mantiene en alto su propio start_reset.
// Un pulso de un ciclo que caiga en esa ventana se pierde sin dejar
// rastro, y quien espera se queda esperando para siempre. Por eso aqui
// la peticion se convierte en un nivel que se mantiene hasta que el
// nucleo confirma el fin: en cuanto la ventana se cierra, el nucleo la
// toma.
//
// El efecto es que entre dos bytes seguidos la linea queda en reposo
// unos tres tiempos de bit en vez de uno. La trama sigue siendo correcta
// -reposo de mas entre caracteres siempre es valido- y el mensaje mas
// largo pasa de 3.0 ms a unos 4.0 ms, que no significa nada frente al
// segundo de resolucion del juego.
// =====================================================================

module uart_core #(
    // ciclos por bit en transmision
    parameter int BAUD_DIV     = 868,
    // ciclos por muestra en recepcion, con sobremuestreo por 16
    parameter int BAUD_X16_DIV = 54
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

    logic tx_fin;          // pulso de un ciclo al terminar un byte
    logic peticion_q = 1'b0;

    // La peticion se levanta al recibir el pulso y se mantiene hasta que
    // el nucleo avisa del fin. Mientras esta alta, el periferico ve el
    // canal ocupado.
    always_ff @(posedge clk_i) begin
        if (rst_i)               peticion_q <= 1'b0;
        else if (tx_start_i)     peticion_q <= 1'b1;
        else if (tx_fin)         peticion_q <= 1'b0;
    end

    assign tx_busy_o = peticion_q;

    UART_tx #(
        .BAUD_CLK_TICKS(BAUD_DIV)
    ) transmisor (
        .clk         (clk_i),
        .reset       (rst_i),
        .tx_start    (peticion_q),
        .tx_rdy      (tx_fin),
        .tx_data_in  (tx_data_i),
        .tx_data_out (tx_o)
    );

    UART_rx #(
        .BAUD_X16_CLK_TICKS(BAUD_X16_DIV)
    ) receptor (
        .clk         (clk_i),
        .reset       (rst_i),
        .rx_data_in  (rx_i),
        .rx_data_rdy (rx_valid_o),
        .rx_data_out (rx_data_o)
    );

endmodule
