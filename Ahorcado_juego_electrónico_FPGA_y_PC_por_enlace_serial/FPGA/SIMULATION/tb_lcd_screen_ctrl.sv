// =====================================================================
// tb_lcd_screen_ctrl.sv - Testbench autoverificable de la capa de pantalla
//
// Se prueba la cadena completa: capa de pantalla, periferico y
// controlador reales. El monitor lee lo que llega al modulo LCD en el
// flanco de bajada de E y reconstruye las dos lineas de texto, que es lo
// que de verdad veria el jugador. Comparar texto contra texto permite
// contrastar directamente con las pantallas del documento de diseno.
//
// Comprueba:
//   1. cada redibujado son 34 transacciones: dos comandos y 32 caracteres
//   2. los comandos de direccion son 0x80 y 0xC0 y salen con rs en cero
//   3. los 32 caracteres salen con rs en uno
//   4. pantalla de seleccion: titulo con el contador de victorias y modo
//   5. pantalla de partida: patron con guiones e intentos restantes
//   6. las tres pantallas de resultado, con la palabra completa debajo
//   7. las lineas se rellenan con espacios hasta la columna 16
//   8. una orden que llega durante un redibujado se ignora
//   9. los datos se copian al empezar: cambiarlos a mitad no altera la
//      pantalla que se esta dibujando
//  10. busy_o sube al aceptar la orden y baja al terminar
// =====================================================================
`timescale 1ns/1ps

module tb_lcd_screen_ctrl;

    localparam int MAX_LEN = 12;
    localparam int N_COL   = 16;

    // tiempos reducidos: aqui se verifica el contenido y la secuencia, no
    // la duracion real de las esperas del LCD
    localparam int POWERON_TICKS = 2;
    localparam int CIC_CORTA     = 12;
    localparam int CIC_LARGA     = 30;
    localparam int CIC_SETUP     = 3;
    localparam int CIC_E_ALTO    = 3;
    localparam int CIC_E_BAJO    = 3;
    localparam int TICK_DIV      = 4;

    localparam logic [2:0] SCR_SELECT      = 3'd0;
    localparam logic [2:0] SCR_PLAY        = 3'd1;
    localparam logic [2:0] SCR_WIN         = 3'd2;
    localparam logic [2:0] SCR_LOSE_FALLOS = 3'd3;
    localparam logic [2:0] SCR_LOSE_TIEMPO = 3'd4;

    localparam logic [8*MAX_LEN-1:0] W_TECLADO = "TECLADO     ";
    localparam logic [8*MAX_LEN-1:0] W_SOL     = "SOL         ";

    logic clk = 1'b0;
    logic rst = 1'b0;

    logic [2:0] screen = SCR_SELECT;
    logic       redraw = 1'b0;
    logic       busy_s;

    logic [8*MAX_LEN-1:0] wdata_w = W_TECLADO;
    logic [3:0]           wlen    = 4'd7;
    logic [MAX_LEN-1:0]   rev     = '0;
    logic [2:0]           errores_j = 3'd0;
    logic                 modo    = 1'b0;
    logic [7:0]           wins    = 8'h00;

    logic        we;
    logic [1:0]  addr;
    logic [31:0] wdata, rdata;

    logic       start_p, rs_p;
    logic [7:0] data_p;
    logic       busy_c, done_c;

    logic [7:0] db;
    logic       lcd_rs, lcd_rw, lcd_e;

    int errores = 0;
    int n_cap   = 0;
    logic [7:0] cap_db [0:63];
    logic       cap_rs [0:63];

    always #5 clk = ~clk;

    int tick_cnt = 0;
    logic tick;
    assign tick = (tick_cnt == TICK_DIV - 1);
    always_ff @(posedge clk) tick_cnt <= tick ? 0 : tick_cnt + 1;

    lcd_screen_ctrl #(.MAX_LEN(MAX_LEN)) dut (
        .clk_i(clk), .rst_i(rst),
        .screen_i(screen), .redraw_i(redraw), .busy_o(busy_s),
        .word_data_i(wdata_w), .word_len_i(wlen), .revealed_i(rev),
        .errors_i(errores_j), .mode_i(modo), .wins_i(wins),
        .write_enable_o(we), .addr_o(addr), .wdata_o(wdata), .rdata_i(rdata)
    );

    lcd_peripheral periferico (
        .clk_i(clk), .rst_i(rst),
        .write_enable_i(we), .addr_i(addr), .wdata_i(wdata), .rdata_o(rdata),
        .start_o(start_p), .rs_o(rs_p), .data_o(data_p),
        .busy_i(busy_c), .done_i(done_c)
    );

    lcd_controller #(
        .POWERON_TICKS(POWERON_TICKS), .CIC_CORTA(CIC_CORTA), .CIC_LARGA(CIC_LARGA),
        .CIC_SETUP(CIC_SETUP), .CIC_E_ALTO(CIC_E_ALTO), .CIC_E_BAJO(CIC_E_BAJO)
    ) lcd (
        .clk_i(clk), .rst_i(rst), .tick_i(tick),
        .start_i(start_p), .rs_i(rs_p), .data_i(data_p),
        .busy_o(busy_c), .done_o(done_c),
        .lcd_db_o(db), .lcd_rs_o(lcd_rs), .lcd_rw_o(lcd_rw), .lcd_e_o(lcd_e)
    );

    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $display("  FAIL: %s", msg);
            errores++;
        end
    endtask

    // ---- monitor del bus del modulo ----
    initial begin
        forever begin
            @(negedge lcd_e);
            if (n_cap < 64) begin
                cap_db[n_cap] = db;
                cap_rs[n_cap] = lcd_rs;
                n_cap++;
            end
        end
    end

    // ---- orden de dibujo ----
    task automatic dibujar(input logic [2:0] s);
        int guardia;
        @(negedge clk);
        screen = s;
        n_cap  = 0;
        redraw = 1'b1;
        @(negedge clk);
        redraw = 1'b0;
        check(busy_s === 1'b1, "la capa no se declaro ocupada al aceptar la orden");
        guardia = 0;
        while (busy_s && guardia < 200000) begin
            @(posedge clk);
            guardia++;
        end
        check(guardia < 200000, "el redibujado no termino nunca");
        repeat (2) @(negedge clk);
    endtask

    // Reconstruye lo capturado y lo compara con las dos lineas esperadas.
    function automatic void comprobar(input string l0, input string l1,
                                      input string nombre);
        string v0, v1;
        int i;
        if (n_cap != 34) begin
            $display("  FAIL: %s: se esperaban 34 transacciones y hubo %0d",
                     nombre, n_cap);
            errores++;
            return;
        end
        if (cap_db[0] !== 8'h80 || cap_rs[0] !== 1'b0) begin
            $display("  FAIL: %s: la fila 0 no se direcciono con 0x80 y rs en cero",
                     nombre);
            errores++;
        end
        if (cap_db[17] !== 8'hC0 || cap_rs[17] !== 1'b0) begin
            $display("  FAIL: %s: la fila 1 no se direcciono con 0xC0 y rs en cero",
                     nombre);
            errores++;
        end
        v0 = "";
        v1 = "";
        for (i = 0; i < N_COL; i++) begin
            if (cap_rs[1 + i] !== 1'b1 || cap_rs[18 + i] !== 1'b1) begin
                $display("  FAIL: %s: un caracter salio con rs en cero (columna %0d)",
                         nombre, i);
                errores++;
            end
            v0 = {v0, string'(cap_db[1  + i])};
            v1 = {v1, string'(cap_db[18 + i])};
        end
        if (v0 != l0) begin
            $display("  FAIL: %s linea 0", nombre);
            $display("        esperado [%s]", l0);
            $display("        obtenido [%s]", v0);
            errores++;
        end
        if (v1 != l1) begin
            $display("  FAIL: %s linea 1", nombre);
            $display("        esperado [%s]", l1);
            $display("        obtenido [%s]", v1);
            errores++;
        end
    endfunction

    initial begin
        int n_antes;
        $display("");
        $display("=== tb_lcd_screen_ctrl ===");

        // el LCD arranca solo; hasta que termine no se puede dibujar nada
        check(busy_s === 1'b0, "la capa deberia estar libre antes de la primera orden");
        wait (!busy_c);
        repeat (4) @(negedge clk);

        // ---------- 4: pantalla de seleccion ----------
        wins = 8'h07;
        modo = 1'b0;
        dibujar(SCR_SELECT);
        comprobar("AHORCADO  V:07  ", "MODO: FACIL     ", "seleccion facil");

        wins = 8'h99;
        modo = 1'b1;
        dibujar(SCR_SELECT);
        comprobar("AHORCADO  V:99  ", "MODO: DIFICIL   ", "seleccion dificil");

        // ---------- 5: pantalla de partida ----------
        wdata_w   = W_TECLADO;
        wlen      = 4'd7;
        rev       = 12'b0000_0000_1001;   // reveladas las posiciones 0 y 3
        errores_j = 3'd2;
        modo      = 1'b1;
        dibujar(SCR_PLAY);
        comprobar("T__L___         ", "INTENTOS: 4    D", "partida");

        // sin errores y en facil
        rev       = 12'b0000_0000_0000;
        errores_j = 3'd0;
        modo      = 1'b0;
        dibujar(SCR_PLAY);
        comprobar("_______         ", "INTENTOS: 6    F", "partida sin aciertos");

        // con los seis errores gastados
        rev       = 12'b0000_0111_1111;   // palabra completa
        errores_j = 3'd6;
        dibujar(SCR_PLAY);
        comprobar("TECLADO         ", "INTENTOS: 0    F", "partida sin intentos");

        // palabra corta: el resto de la linea son espacios
        wdata_w   = W_SOL;
        wlen      = 4'd3;
        rev       = 12'b0000_0000_0010;
        errores_j = 3'd1;
        dibujar(SCR_PLAY);
        comprobar("_O_             ", "INTENTOS: 5    F", "palabra corta");

        // ---------- 6: pantallas de resultado ----------
        wdata_w = W_TECLADO;
        wlen    = 4'd7;
        dibujar(SCR_WIN);
        comprobar("   GANASTE!     ", "TECLADO         ", "victoria");

        dibujar(SCR_LOSE_FALLOS);
        comprobar("PERDISTE: FALLOS", "TECLADO         ", "derrota por fallos");

        dibujar(SCR_LOSE_TIEMPO);
        comprobar("PERDISTE: TIEMPO", "TECLADO         ", "derrota por tiempo");

        // ---------- 8: orden durante un redibujado ----------
        // Se lanza una pantalla y en plena escritura se pide otra: la
        // segunda debe perderse y no meter transacciones de mas.
        @(negedge clk);
        screen = SCR_WIN;
        n_cap  = 0;
        redraw = 1'b1;
        @(negedge clk);
        redraw = 1'b0;
        repeat (20 * CIC_CORTA) @(negedge clk);       // ya va por media pantalla
        check(busy_s === 1'b1, "hacia falta que estuviera dibujando para esta prueba");
        screen = SCR_LOSE_TIEMPO;
        redraw = 1'b1;
        @(negedge clk);
        redraw = 1'b0;
        while (busy_s) @(posedge clk);
        repeat (2) @(negedge clk);
        comprobar("   GANASTE!     ", "TECLADO         ", "orden ignorada durante el dibujo");

        // ---------- 9: los datos se copian al empezar ----------
        wdata_w   = W_TECLADO;
        wlen      = 4'd7;
        rev       = 12'b0000_0000_1001;
        errores_j = 3'd2;
        modo      = 1'b1;
        @(negedge clk);
        screen = SCR_PLAY;
        n_cap  = 0;
        redraw = 1'b1;
        @(negedge clk);
        redraw = 1'b0;
        repeat (10 * CIC_CORTA) @(negedge clk);
        // cambio brusco de todas las entradas a mitad del dibujo
        wdata_w   = W_SOL;
        wlen      = 4'd3;
        rev       = 12'b1111_1111_1111;
        errores_j = 3'd5;
        modo      = 1'b0;
        while (busy_s) @(posedge clk);
        repeat (2) @(negedge clk);
        comprobar("T__L___         ", "INTENTOS: 4    D", "datos copiados al empezar");

        // ---------- 10: al terminar queda libre ----------
        check(busy_s === 1'b0, "la capa quedo ocupada despues de terminar");
        n_antes = n_cap;
        repeat (200) @(negedge clk);
        check(n_cap == n_antes, "siguio escribiendo sin que nadie se lo pidiera");

        $display("");
        if (errores == 0)
            $display("  PASS  las seis pantallas, el relleno, el descarte y la copia de datos son correctos");
        else
            $display("  FAIL  %0d comprobaciones fallidas", errores);
        $display("");
        $finish;
    end

endmodule
