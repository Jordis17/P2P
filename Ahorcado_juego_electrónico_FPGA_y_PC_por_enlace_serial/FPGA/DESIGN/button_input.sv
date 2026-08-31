// =====================================================================
// button_input.sv - Acondicionamiento de un pulsador
//
//   btn_i --> sincronizador 2 FF --> filtro de rebotes --> flanco
//
// Tres etapas, cada una resolviendo un problema distinto:
//
// 1. Sincronizador. El pulsador cambia en cualquier instante respecto al
//    reloj, asi que puede violar los tiempos de establecimiento del
//    primer flip-flop y dejarlo metaestable. El segundo le da un ciclo
//    completo para resolverse.
//
// 2. Filtro de rebotes. Los contactos mecanicos oscilan durante unos
//    pocos milisegundos. El contador solo avanza mientras la entrada
//    sincronizada difiere del nivel estable; cualquier oscilacion lo
//    devuelve a cero. Solo un nivel sostenido durante DEBOUNCE_MS
//    completos consigue cambiar el estado.
//
// 3. Detector de flanco. Sin el, la FSM veria el boton presionado
//    durante millones de ciclos y cambiaria de modo miles de veces con
//    una sola pulsacion.
//
// La polaridad se normaliza en la entrada, de modo que internamente uno
// siempre significa presionado.
//
// Los registros declaran valor inicial para que el modulo arranque en un
// estado conocido tras la configuracion, sin depender del reset.
// =====================================================================

module button_input #(
    parameter int   DEBOUNCE_MS      = 10,
    parameter logic BTN_ACTIVE_LEVEL = 1'b1
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic tick_i,     // pulso de 1 ms
    input  logic btn_i,      // entrada fisica, asincrona
    output logic pulse_o,    // un ciclo por pulsacion
    output logic level_o     // nivel ya filtrado
);

    localparam int W = (DEBOUNCE_MS <= 1) ? 1 : $clog2(DEBOUNCE_MS);

    logic         btn_norm;
    logic         sync_q1  = 1'b0;
    logic         sync_q2  = 1'b0;
    logic         stable_q = 1'b0;
    logic         stable_d = 1'b0;
    logic [W-1:0] cnt_q    = '0;

    // Normalizacion de polaridad: a partir de aqui 1 = presionado
    assign btn_norm = (btn_i == BTN_ACTIVE_LEVEL);

    assign level_o = stable_q;
    assign pulse_o = stable_q & ~stable_d;   // solo flanco de subida

    // Etapa 1: sincronizador de dos etapas
    always_ff @(posedge clk_i) begin
        sync_q1 <= btn_norm;
        sync_q2 <= sync_q1;
    end

    // Etapa 2: filtro de rebotes
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            cnt_q    <= '0;
            stable_q <= 1'b0;
        end else if (sync_q2 == stable_q) begin
            cnt_q    <= '0;                  // sin desacuerdo, se reinicia
        end else if (tick_i) begin
            if (cnt_q == W'(DEBOUNCE_MS - 1)) begin
                stable_q <= sync_q2;         // desacuerdo sostenido, se adopta
                cnt_q    <= '0;
            end else begin
                cnt_q    <= cnt_q + 1'b1;
            end
        end
    end

    // Etapa 3: retardo de un ciclo para detectar el flanco
    always_ff @(posedge clk_i) begin
        if (rst_i) stable_d <= 1'b0;
        else       stable_d <= stable_q;
    end

endmodule
