// =====================================================================
// led_controller.sv - Indicadores de estado y de modo
//
// Bloque puramente combinacional, sin estado propio.
//
//   led_o[0]  encendido en seleccion de modo
//   led_o[1]  encendido en partida en curso
//   led_o[2]  encendido mostrando el resultado
//   led_o[15] modo: apagado = facil, encendido = dificil
//
// Los tres primeros son mutuamente excluyentes: exactamente uno esta
// encendido en todo momento. El testbench lo comprueba, porque si alguna
// vez fallara significaria que el control esta en un estado no previsto.
//
// Se usan tres LEDs y no uno solo porque las tres etapas deben ser
// distinguibles a simple vista. Con un unico LED habria que codificarlas
// por parpadeo, lo que obliga a esperar para saber en que estado esta el
// sistema. La tarjeta tiene dieciseis LEDs, asi que dedicar uno a cada
// etapa no cuesta recursos y reduce la logica a un decodificador de 2 a 3.
//
// La polaridad se aplica al final: internamente uno significa encendido.
// Con LED_ACTIVE_LEVEL = 0 la inversion tambien deja apagados los LEDs no
// utilizados, porque su valor logico es cero.
// =====================================================================

module led_controller #(
    parameter logic LED_ACTIVE_LEVEL = 1'b1
) (
    input  logic [1:0]  state_i,   // 00 seleccion, 01 partida, 10 resultado
    input  logic        mode_i,    // 0 facil, 1 dificil
    output logic [15:0] led_o
);

    logic [15:0] led;

    always_comb begin
        led = '0;
        unique case (state_i)
            2'b00:   led[0] = 1'b1;
            2'b01:   led[1] = 1'b1;
            2'b10:   led[2] = 1'b1;
            2'b11:   led    = '0;   // codigo no usado: los tres apagados
            default: led    = '0;
        endcase
        led[15] = mode_i;
    end

    assign led_o = LED_ACTIVE_LEVEL ? led : ~led;

endmodule
