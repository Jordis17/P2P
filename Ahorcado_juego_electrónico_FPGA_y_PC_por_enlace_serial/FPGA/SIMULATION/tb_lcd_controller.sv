// =====================================================================
// tb_lcd_controller.sv - Testbench autoverificable del controlador LCD
//
// Un monitor permanente captura cada byte que el controlador entrega al
// modulo, muestreandolo en el flanco de bajada de E, que es donde el
// KS0066 lo toma. El mismo monitor comprueba en cada transaccion que los
// datos y rs estuvieron estables durante todo el pulso de E: si el bus
// cambiara mientras E esta alto, el LCD podria capturar un valor
// intermedio.
//
// Comprueba:
//   1. al arrancar, el controlador esta ocupado y no acepta peticiones
//   2. la espera de encendido dura lo configurado antes del primer comando
//   3. la inicializacion emite 0x38, 0x0C, 0x01 y 0x06 con rs en cero
//   4. al terminar la inicializacion baja la senal de ocupado
//   5. una escritura de dato sale con rs en uno y el byte correcto
//   6. datos y rs permanecen estables durante todo el pulso de E
//   7. rw se mantiene en cero siempre
//   8. la senal de fin pulsa un solo ciclo por operacion
//   9. un comando de limpieza usa la espera larga y una escritura la corta
//  10. una peticion recibida con el controlador ocupado se descarta
//  11. un reinicio no repite la secuencia de arranque
// =====================================================================
`timescale 1ns/1ps

module tb_lcd_controller;

    localparam int POWERON_TICKS = 4;
    localparam int CIC_CORTA     = 40;
    localparam int CIC_LARGA     = 300;
    localparam int CIC_SETUP     = 5;
    localparam int CIC_E_ALTO    = 8;
    localparam int CIC_E_BAJO    = 8;
    localparam int TICK_DIV      = 4;

    logic clk = 1'b0;
    logic rst = 1'b0;
    logic start = 1'b0;
    logic rs = 1'b0;
    logic [7:0] data = 8'h00;
    logic busy, done;
    logic [7:0] db;
    logic lcd_rs, lcd_rw, lcd_e;

    int errores = 0;
    int n_cap = 0;
    logic [7:0] cap_db  [0:31];
    logic       cap_rs  [0:31];
    int         cap_t   [0:31];      // instante del flanco de bajada, en ciclos
    int n_done = 0;
    int ciclo = 0;
    int k, t_ini, t_fin;

    always #5 clk = ~clk;
    always_ff @(posedge clk) ciclo <= ciclo + 1;

    int tick_cnt = 0;
    logic tick;
    assign tick = (tick_cnt == TICK_DIV - 1);
    always_ff @(posedge clk) tick_cnt <= tick ? 0 : tick_cnt + 1;

    lcd_controller #(
        .POWERON_TICKS(POWERON_TICKS), .CIC_CORTA(CIC_CORTA), .CIC_LARGA(CIC_LARGA),
        .CIC_SETUP(CIC_SETUP), .CIC_E_ALTO(CIC_E_ALTO), .CIC_E_BAJO(CIC_E_BAJO)
    ) dut (
        .clk_i(clk), .rst_i(rst), .tick_i(tick),
        .start_i(start), .rs_i(rs), .data_i(data),
        .busy_o(busy), .done_o(done),
        .lcd_db_o(db), .lcd_rs_o(lcd_rs), .lcd_rw_o(lcd_rw), .lcd_e_o(lcd_e)
    );

    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $display("  FAIL: %s", msg);
            errores++;
        end
    endtask

    // ---- monitor: captura en el flanco de bajada de E y vigila estabilidad ----
    logic [7:0] db_al_subir;
    logic       rs_al_subir;
    initial begin
        forever begin
            @(posedge lcd_e);
            db_al_subir = db;
            rs_al_subir = lcd_rs;
            // vigilar el bus mientras E esta alto
            while (lcd_e) begin
                if (db !== db_al_subir) begin
                    $display("  FAIL: los datos cambiaron con E en alto");
                    errores++;
                end
                if (lcd_rs !== rs_al_subir) begin
                    $display("  FAIL: rs cambio con E en alto");
                    errores++;
                end
                @(posedge clk);
            end
            // flanco de bajada: el LCD toma el dato aqui
            if (n_cap < 32) begin
                cap_db[n_cap] = db;
                cap_rs[n_cap] = lcd_rs;
                cap_t [n_cap] = ciclo;
                n_cap++;
            end
        end
    end

    // rw nunca debe moverse
    always @(posedge clk) if (lcd_rw !== 1'b0) begin
        $display("  FAIL: rw dejo de estar en cero");
        errores++;
    end

    always @(posedge clk) if (done) n_done++;

    task automatic pedir(input logic r, input logic [7:0] d);
        @(negedge clk);
        rs    = r;
        data  = d;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
    endtask

    initial begin
        $display("");
        $display("=== tb_lcd_controller ===");

        // ---------- 1: ocupado al arrancar ----------
        @(negedge clk);
        check(busy === 1'b1, "deberia estar ocupado durante el arranque");
        check(n_cap == 0, "emitio algo antes de cumplir la espera de encendido");

        // ---------- 2: la espera de encendido se respeta ----------
        repeat (POWERON_TICKS * TICK_DIV - 4) @(negedge clk);
        check(n_cap == 0, "emitio el primer comando antes de tiempo");

        // ---------- 3: los cuatro comandos de inicializacion ----------
        wait (n_cap == 4);
        check(cap_db[0] == 8'h38, $sformatf("init 1: se esperaba 0x38 y salio 0x%02h", cap_db[0]));
        check(cap_db[1] == 8'h0C, $sformatf("init 2: se esperaba 0x0C y salio 0x%02h", cap_db[1]));
        check(cap_db[2] == 8'h01, $sformatf("init 3: se esperaba 0x01 y salio 0x%02h", cap_db[2]));
        check(cap_db[3] == 8'h06, $sformatf("init 4: se esperaba 0x06 y salio 0x%02h", cap_db[3]));
        for (k = 0; k < 4; k++)
            check(cap_rs[k] === 1'b0,
                  $sformatf("init %0d: rs deberia ser cero", k + 1));

        // el tercer comando es Clear y debe ir seguido de la espera larga
        check((cap_t[3] - cap_t[2]) > (cap_t[2] - cap_t[1]),
              "tras el Clear de inicializacion no se espero mas que tras los otros");

        // ---------- 4: libre al terminar ----------
        wait (!busy);
        @(negedge clk);
        check(busy === 1'b0, "deberia quedar libre al terminar la inicializacion");
        check(n_done == 0, "la inicializacion no deberia generar senal de fin");

        // ---------- 5, 6, 8: escritura de un dato ----------
        n_done = 0;
        pedir(1'b1, 8'h41);                  // 'A' como dato
        wait (n_cap == 5);
        check(cap_db[4] == 8'h41, $sformatf("se esperaba 0x41 y salio 0x%02h", cap_db[4]));
        check(cap_rs[4] === 1'b1, "una escritura de dato debe llevar rs en uno");
        wait (!busy);
        // La senal de fin se levanta en el mismo flanco en que baja la de
        // ocupado, y el contador del testbench la muestrea en el flanco
        // siguiente. Comprobar de inmediato seria mirar antes de que el
        // contador haya podido verla.
        repeat (3) @(negedge clk);
        check(n_done == 1,
              $sformatf("la senal de fin pulso %0d veces, se esperaba 1", n_done));

        // ---------- 9: comparacion de esperas ----------
        t_ini = ciclo;
        pedir(1'b0, 8'h80);                  // comando corto: fijar direccion
        wait (!busy);
        t_fin = ciclo;
        k = t_fin - t_ini;                   // duracion de la operacion corta

        t_ini = ciclo;
        pedir(1'b0, 8'h01);                  // Clear: espera larga
        wait (!busy);
        t_fin = ciclo;
        check((t_fin - t_ini) > k,
              $sformatf("el Clear duro %0d ciclos y la escritura corta %0d",
                        t_fin - t_ini, k));

        // ---------- 10: peticion con el controlador ocupado ----------
        n_cap = 0;
        pedir(1'b1, 8'h42);                  // 'B'
        @(negedge clk);
        pedir(1'b1, 8'h43);                  // 'C' mientras la anterior sigue
        wait (!busy);
        repeat (CIC_CORTA) @(negedge clk);
        check(n_cap == 1,
              $sformatf("se emitieron %0d bytes, la segunda peticion debio descartarse", n_cap));
        check(cap_db[0] == 8'h42,
              $sformatf("se emitio 0x%02h en vez de 0x42", cap_db[0]));

        // ---------- 11: el reinicio no repite el arranque ----------
        n_cap = 0;
        @(negedge clk);
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (POWERON_TICKS * TICK_DIV * 2) @(negedge clk);
        check(n_cap == 0,
              "el reinicio volvio a lanzar la secuencia de arranque");
        check(busy === 1'b0, "tras el reinicio deberia quedar libre");

        // y sigue aceptando peticiones normales
        pedir(1'b1, 8'h5A);                  // 'Z'
        wait (!busy);
        check(n_cap == 1 && cap_db[0] == 8'h5A,
              "tras el reinicio no acepta peticiones normales");

        $display("");
        if (errores == 0)
            $display("  PASS  arranque, inicializacion, ciclo de bus, esperas y reinicio correctos");
        else
            $display("  FAIL  %0d comprobaciones fallidas", errores);
        $display("");
        $finish;
    end

endmodule
