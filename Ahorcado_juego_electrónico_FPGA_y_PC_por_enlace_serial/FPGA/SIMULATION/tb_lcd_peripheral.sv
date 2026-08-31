// =====================================================================
// tb_lcd_peripheral.sv - Testbench autoverificable del periferico LCD
//
// Se prueba el periferico junto al controlador real, no contra un modelo:
// lo que interesa comprobar no es solo que los registros guarden bits,
// sino que una escritura en el mapa de registros termine convertida en el
// byte correcto sobre el bus del modulo. Por eso el monitor observa las
// patas del LCD y captura cada byte en el flanco de bajada de E, igual
// que en el testbench del controlador.
//
// Comprueba:
//   1. tras el arranque los registros leen cero y la senal de fin esta baja
//   2. el registro de datos guarda y devuelve el byte escrito
//   3. rs es un bit normal de lectura y escritura
//   4. una peticion de envio emite el byte guardado con el rs de esa misma
//      escritura
//   5. la senal de arranque hacia el controlador dura un solo ciclo
//   6. una limpieza emite 0x01 con rs en cero sin tocar el registro de datos
//   7. un retorno al inicio emite 0x02 con rs en cero
//   8. con varios bits de solicitud a la vez se aplica clear > home > start
//   9. una peticion recibida con el periferico ocupado se descarta
//  10. el bit de ocupado refleja el estado del controlador
//  11. el bit de fin se queda puesto y solo se limpia al aceptar otra
//      peticion
//  12. los bits de solicitud se leen siempre como cero
//  13. las direcciones no usadas leen cero
//
// Ejecutar:
//   iverilog -g2012 -o tb tb_lcd_peripheral.sv \
//            ../DESIGN/lcd_peripheral.sv ../DESIGN/lcd_controller.sv
//   ./tb
// =====================================================================
`timescale 1ns/1ps

module tb_lcd_peripheral;

    // Tiempos reducidos: aqui se verifica el protocolo de registros, no la
    // duracion real de las esperas, que ya se comprobo en su testbench.
    localparam int POWERON_TICKS = 2;
    localparam int CIC_CORTA     = 20;
    localparam int CIC_LARGA     = 60;
    localparam int CIC_SETUP     = 4;
    localparam int CIC_E_ALTO    = 4;
    localparam int CIC_E_BAJO    = 4;
    localparam int TICK_DIV      = 4;

    // posiciones dentro del registro de control
    localparam int B_START = 0;
    localparam int B_RS    = 1;
    localparam int B_CLEAR = 2;
    localparam int B_HOME  = 3;
    localparam int B_BUSY  = 8;
    localparam int B_DONE  = 9;

    localparam logic [1:0] A_CTRL  = 2'b00;
    localparam logic [1:0] A_DATOS = 2'b01;

    logic        clk = 1'b0;
    logic        rst = 1'b0;
    logic        we  = 1'b0;
    logic [1:0]  addr = 2'b00;
    logic [31:0] wdata = 32'd0;
    logic [31:0] rdata;

    logic       start_p, rs_p;
    logic [7:0] data_p;
    logic       busy_c, done_c;

    logic [7:0] db;
    logic       lcd_rs, lcd_rw, lcd_e;

    int errores = 0;
    int n_cap   = 0;
    int n_start = 0;
    logic [7:0] cap_db [0:31];
    logic       cap_rs [0:31];
    logic [31:0] val;

    always #5 clk = ~clk;

    // generador del pulso de 1 ms que consume el controlador
    int tick_cnt = 0;
    logic tick;
    assign tick = (tick_cnt == TICK_DIV - 1);
    always_ff @(posedge clk) tick_cnt <= tick ? 0 : tick_cnt + 1;

    lcd_peripheral dut (
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

    // ---- monitor permanente del bus del modulo ----
    initial begin
        forever begin
            @(negedge lcd_e);
            if (n_cap < 32) begin
                cap_db[n_cap] = db;
                cap_rs[n_cap] = lcd_rs;
                n_cap++;
            end
        end
    end

    // La senal de arranque debe ser un pulso: se cuenta cuantos ciclos
    // pasa en alto para detectar un nivel mantenido por error.
    always @(posedge clk) if (start_p) n_start++;

    // ---- maestro del bus de registros ----
    task automatic escribir(input logic [1:0] a, input logic [31:0] d);
        @(negedge clk);
        addr  = a;
        wdata = d;
        we    = 1'b1;
        @(negedge clk);
        we    = 1'b0;
        wdata = 32'd0;
    endtask

    task automatic leer(input logic [1:0] a, output logic [31:0] d);
        @(negedge clk);
        addr = a;
        @(negedge clk);
        d = rdata;
    endtask

    // Entre la escritura del registro y la subida de la senal de ocupado
    // pasan dos ciclos: uno para que el periferico emita el pulso de
    // arranque y otro para que el controlador lo tome. Mirar el ocupado
    // antes de eso lo encontraria todavia en cero, asi que la espera de
    // una operacion tiene dos mitades: primero que suba y despues que baje.
    task automatic esperar_arranque;
        int guardia;
        guardia = 0;
        while (!busy_c && guardia < 100) begin
            @(posedge clk);
            guardia++;
        end
        check(guardia < 100, "el controlador no arranco tras la peticion");
    endtask

    task automatic esperar_libre;
        int guardia;
        guardia = 0;
        while (busy_c && guardia < 5000) begin
            @(posedge clk);
            guardia++;
        end
        check(guardia < 5000, "el controlador nunca solto la senal de ocupado");
    endtask

    // Los dos flancos finales dan margen a que el periferico registre el
    // aviso de fin, que llega el ciclo siguiente a soltarse el ocupado.
    task automatic esperar_operacion;
        esperar_arranque;
        esperar_libre;
        repeat (2) @(negedge clk);
    endtask

    initial begin
        $display("");
        $display("=== tb_lcd_peripheral ===");

        // El controlador arranca solo con su secuencia de encendido. Hasta
        // que termine, todo lo que se pida se descarta, asi que se espera.
        esperar_libre;
        n_cap   = 0;      // se descartan los cuatro bytes de inicializacion
        n_start = 0;

        // ---------- 1: estado de partida ----------
        leer(A_CTRL, val);
        check(val == 32'd0, $sformatf("el control deberia leer cero y leyo 0x%08h", val));
        leer(A_DATOS, val);
        check(val == 32'd0, $sformatf("los datos deberian leer cero y leyeron 0x%08h", val));

        // ---------- 2: el registro de datos guarda ----------
        escribir(A_DATOS, 32'h0000_0041);            // 'A'
        leer(A_DATOS, val);
        check(val == 32'h0000_0041,
              $sformatf("el registro de datos devolvio 0x%08h", val));
        check(n_cap == 0, "escribir en datos no debe emitir nada al modulo");

        // ---------- 3: rs es un bit normal ----------
        escribir(A_CTRL, 32'd1 << B_RS);
        leer(A_CTRL, val);
        check(val[B_RS] === 1'b1, "rs no se guardo");
        check(n_cap == 0, "escribir rs no debe emitir nada al modulo");

        // ---------- 4 y 5: envio de un caracter ----------
        escribir(A_CTRL, (32'd1 << B_RS) | (32'd1 << B_START));
        esperar_arranque;
        check(busy_c === 1'b1, "el controlador deberia haber arrancado");
        leer(A_CTRL, val);
        check(val[B_BUSY] === 1'b1, "el bit de ocupado no reflejo el estado real");
        check(val[B_DONE] === 1'b0, "el bit de fin no deberia estar puesto aun");
        // 12: los bits de solicitud no guardan estado
        check(val[B_START] === 1'b0 && val[B_CLEAR] === 1'b0 && val[B_HOME] === 1'b0,
              "los bits de solicitud deberian leerse como cero");

        esperar_libre;
        repeat (2) @(negedge clk);
        check(n_cap == 1, $sformatf("se esperaba un byte emitido y hubo %0d", n_cap));
        check(cap_db[0] == 8'h41,
              $sformatf("se emitio 0x%02h en vez de 0x41", cap_db[0]));
        check(cap_rs[0] === 1'b1, "el caracter salio con rs en cero");
        check(n_start == 1,
              $sformatf("la senal de arranque estuvo alta %0d ciclos", n_start));

        // ---------- 11: el bit de fin se queda puesto ----------
        leer(A_CTRL, val);
        check(val[B_DONE] === 1'b1, "el bit de fin no se levanto");
        repeat (20) @(posedge clk);
        leer(A_CTRL, val);
        check(val[B_DONE] === 1'b1, "el bit de fin se borro solo");

        // ---------- rs sale de la escritura que pide el envio ----------
        // rs quedo en uno; se pide un envio sin poner rs y debe salir en cero
        n_cap = 0;
        escribir(A_DATOS, 32'h0000_0042);            // 'B'
        escribir(A_CTRL, 32'd1 << B_START);
        esperar_operacion;
        check(n_cap == 1 && cap_db[0] == 8'h42 && cap_rs[0] === 1'b0,
              "el envio no uso el rs de su propia escritura");
        leer(A_CTRL, val);
        check(val[B_RS] === 1'b0, "el bit rs leido no coincide con el usado");

        // ---------- 6: limpieza ----------
        n_cap   = 0;
        n_start = 0;
        escribir(A_CTRL, 32'd1 << B_CLEAR);
        leer(A_CTRL, val);
        check(val[B_DONE] === 1'b0, "aceptar una peticion no borro el bit de fin");
        esperar_libre;
        repeat (2) @(negedge clk);
        check(n_cap == 1, $sformatf("la limpieza emitio %0d bytes", n_cap));
        check(cap_db[0] == 8'h01,
              $sformatf("la limpieza emitio 0x%02h en vez de 0x01", cap_db[0]));
        check(cap_rs[0] === 1'b0, "la limpieza salio con rs en uno");
        check(n_start == 1, "la limpieza no genero un pulso de arranque limpio");
        leer(A_DATOS, val);
        check(val == 32'h0000_0042, "la limpieza modifico el registro de datos");

        // ---------- 7: retorno al inicio ----------
        n_cap = 0;
        escribir(A_CTRL, 32'd1 << B_HOME);
        esperar_operacion;
        check(n_cap == 1 && cap_db[0] == 8'h02 && cap_rs[0] === 1'b0,
              "el retorno al inicio no emitio 0x02 con rs en cero");

        // ---------- 8: prioridad clear > home > start ----------
        n_cap = 0;
        escribir(A_CTRL, (32'd1 << B_CLEAR) | (32'd1 << B_HOME) |
                         (32'd1 << B_START) | (32'd1 << B_RS));
        esperar_operacion;
        check(n_cap == 1 && cap_db[0] == 8'h01 && cap_rs[0] === 1'b0,
              "con las tres solicitudes juntas no gano la limpieza");

        n_cap = 0;
        escribir(A_CTRL, (32'd1 << B_HOME) | (32'd1 << B_START) | (32'd1 << B_RS));
        esperar_operacion;
        check(n_cap == 1 && cap_db[0] == 8'h02 && cap_rs[0] === 1'b0,
              "entre retorno al inicio y envio no gano el retorno");

        // ---------- 9: peticion con el periferico ocupado ----------
        n_cap = 0;
        escribir(A_DATOS, 32'h0000_0043);            // 'C'
        escribir(A_CTRL, (32'd1 << B_RS) | (32'd1 << B_START));
        esperar_arranque;
        check(busy_c === 1'b1, "hacia falta que estuviera ocupado para esta prueba");
        // segunda peticion en pleno envio: debe perderse
        escribir(A_DATOS, 32'h0000_0044);            // 'D'
        escribir(A_CTRL, (32'd1 << B_RS) | (32'd1 << B_START));
        esperar_libre;
        repeat (CIC_LARGA * 2) @(posedge clk);
        check(n_cap == 1, $sformatf("la peticion con el bus ocupado no se descarto (%0d bytes)", n_cap));
        check(cap_db[0] == 8'h43,
              $sformatf("se emitio 0x%02h en vez de 0x43", cap_db[0]));

        // ---------- 13: direcciones no usadas ----------
        leer(2'b10, val);
        check(val == 32'd0, "una direccion no usada devolvio algo distinto de cero");
        leer(2'b11, val);
        check(val == 32'd0, "una direccion no usada devolvio algo distinto de cero");

        // ---------- reinicio ----------
        n_cap = 0;
        @(negedge clk);
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        leer(A_CTRL, val);
        check(val == 32'd0, $sformatf("tras el reinicio el control leyo 0x%08h", val));
        leer(A_DATOS, val);
        check(val == 32'd0, $sformatf("tras el reinicio los datos leyeron 0x%08h", val));
        check(n_cap == 0, "el reinicio provoco una emision");

        // y sigue funcionando
        escribir(A_DATOS, 32'h0000_005A);            // 'Z'
        escribir(A_CTRL, (32'd1 << B_RS) | (32'd1 << B_START));
        esperar_operacion;
        check(n_cap == 1 && cap_db[0] == 8'h5A && cap_rs[0] === 1'b1,
              "tras el reinicio no vuelve a aceptar envios");

        $display("");
        if (errores == 0)
            $display("  PASS  registros, prioridad, descarte por ocupado y bit de fin correctos");
        else
            $display("  FAIL  %0d comprobaciones fallidas", errores);
        $display("");
        $finish;
    end

endmodule
