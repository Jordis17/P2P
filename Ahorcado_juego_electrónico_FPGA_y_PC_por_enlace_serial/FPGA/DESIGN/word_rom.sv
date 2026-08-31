// =====================================================================
// word_rom.sv - Banco de palabras del Ahorcado
//
// ARCHIVO GENERADO AUTOMATICAMENTE. No editar a mano.
// Fuente: python/gen_word_rom.py
// Regenerar con: python gen_word_rom.py
//
// Orden del banco (de esto depende la seleccion del indice):
//   indices  0..31 -> longitud >= 6 (DIFICIL y FACIL)
//   indices 32..63 -> longitud 4 o 5      (solo FACIL)
//
// Empaquetado de word_data_o:
//   El caracter de la posicion i (i = 0 es el primero de la palabra)
//   ocupa word_data_o[8*(MAX_LEN-1-i) +: 8]. El primer caracter queda
//   en los bits mas significativos, lo que permite escribir cada
//   palabra como un literal de texto legible y revisable.
//   Las posiciones posteriores a word_len_o se rellenan con 8'h20.
//
// Lectura combinacional; el consumidor la registra en START_GAME.
// =====================================================================

module word_rom #(
    parameter int N_WORDS = 64,
    parameter int MAX_LEN = 12
) (
    input  logic [$clog2(N_WORDS)-1:0] index_i,
    output logic [8*MAX_LEN-1:0]    word_data_o,
    output logic [3:0]              word_len_o
);

    always_comb begin
        unique case (index_i)
            6'd0  : begin word_data_o = "PUERTA      "; word_len_o = 4'd6 ; end  // DIFICIL PUERTA
            6'd1  : begin word_data_o = "SENSOR      "; word_len_o = 4'd6 ; end  // DIFICIL SENSOR
            6'd2  : begin word_data_o = "VOLCAN      "; word_len_o = 4'd6 ; end  // DIFICIL VOLCAN
            6'd3  : begin word_data_o = "MADERA      "; word_len_o = 4'd6 ; end  // DIFICIL MADERA
            6'd4  : begin word_data_o = "CAMISA      "; word_len_o = 4'd6 ; end  // DIFICIL CAMISA
            6'd5  : begin word_data_o = "BOTELLA     "; word_len_o = 4'd7 ; end  // DIFICIL BOTELLA
            6'd6  : begin word_data_o = "VENTANA     "; word_len_o = 4'd7 ; end  // DIFICIL VENTANA
            6'd7  : begin word_data_o = "TECLADO     "; word_len_o = 4'd7 ; end  // DIFICIL TECLADO
            6'd8  : begin word_data_o = "MONITOR     "; word_len_o = 4'd7 ; end  // DIFICIL MONITOR
            6'd9  : begin word_data_o = "MEMORIA     "; word_len_o = 4'd7 ; end  // DIFICIL MEMORIA
            6'd10 : begin word_data_o = "SISTEMA     "; word_len_o = 4'd7 ; end  // DIFICIL SISTEMA
            6'd11 : begin word_data_o = "DIGITAL     "; word_len_o = 4'd7 ; end  // DIFICIL DIGITAL
            6'd12 : begin word_data_o = "LAMPARA     "; word_len_o = 4'd7 ; end  // DIFICIL LAMPARA
            6'd13 : begin word_data_o = "ESCUELA     "; word_len_o = 4'd7 ; end  // DIFICIL ESCUELA
            6'd14 : begin word_data_o = "PLANETA     "; word_len_o = 4'd7 ; end  // DIFICIL PLANETA
            6'd15 : begin word_data_o = "CIRCUITO    "; word_len_o = 4'd8 ; end  // DIFICIL CIRCUITO
            6'd16 : begin word_data_o = "REGISTRO    "; word_len_o = 4'd8 ; end  // DIFICIL REGISTRO
            6'd17 : begin word_data_o = "CONTADOR    "; word_len_o = 4'd8 ; end  // DIFICIL CONTADOR
            6'd18 : begin word_data_o = "GUITARRA    "; word_len_o = 4'd8 ; end  // DIFICIL GUITARRA
            6'd19 : begin word_data_o = "ELEFANTE    "; word_len_o = 4'd8 ; end  // DIFICIL ELEFANTE
            6'd20 : begin word_data_o = "MARIPOSA    "; word_len_o = 4'd8 ; end  // DIFICIL MARIPOSA
            6'd21 : begin word_data_o = "TELEFONO    "; word_len_o = 4'd8 ; end  // DIFICIL TELEFONO
            6'd22 : begin word_data_o = "PANTALLA    "; word_len_o = 4'd8 ; end  // DIFICIL PANTALLA
            6'd23 : begin word_data_o = "CUADERNO    "; word_len_o = 4'd8 ; end  // DIFICIL CUADERNO
            6'd24 : begin word_data_o = "BICICLETA   "; word_len_o = 4'd9 ; end  // DIFICIL BICICLETA
            6'd25 : begin word_data_o = "INGENIERO   "; word_len_o = 4'd9 ; end  // DIFICIL INGENIERO
            6'd26 : begin word_data_o = "MICROFONO   "; word_len_o = 4'd9 ; end  // DIFICIL MICROFONO
            6'd27 : begin word_data_o = "VENTILADOR  "; word_len_o = 4'd10; end  // DIFICIL VENTILADOR
            6'd28 : begin word_data_o = "COMPUTADORA "; word_len_o = 4'd11; end  // DIFICIL COMPUTADORA
            6'd29 : begin word_data_o = "LABORATORIO "; word_len_o = 4'd11; end  // DIFICIL LABORATORIO
            6'd30 : begin word_data_o = "HERRAMIENTA "; word_len_o = 4'd11; end  // DIFICIL HERRAMIENTA
            6'd31 : begin word_data_o = "RESISTENCIA "; word_len_o = 4'd11; end  // DIFICIL RESISTENCIA
            6'd32 : begin word_data_o = "CASA        "; word_len_o = 4'd4 ; end  // FACIL   CASA
            6'd33 : begin word_data_o = "MESA        "; word_len_o = 4'd4 ; end  // FACIL   MESA
            6'd34 : begin word_data_o = "SILLA       "; word_len_o = 4'd5 ; end  // FACIL   SILLA
            6'd35 : begin word_data_o = "LIBRO       "; word_len_o = 4'd5 ; end  // FACIL   LIBRO
            6'd36 : begin word_data_o = "PERRO       "; word_len_o = 4'd5 ; end  // FACIL   PERRO
            6'd37 : begin word_data_o = "GATO        "; word_len_o = 4'd4 ; end  // FACIL   GATO
            6'd38 : begin word_data_o = "LUNA        "; word_len_o = 4'd4 ; end  // FACIL   LUNA
            6'd39 : begin word_data_o = "NUBE        "; word_len_o = 4'd4 ; end  // FACIL   NUBE
            6'd40 : begin word_data_o = "FLOR        "; word_len_o = 4'd4 ; end  // FACIL   FLOR
            6'd41 : begin word_data_o = "ARBOL       "; word_len_o = 4'd5 ; end  // FACIL   ARBOL
            6'd42 : begin word_data_o = "CIELO       "; word_len_o = 4'd5 ; end  // FACIL   CIELO
            6'd43 : begin word_data_o = "FUEGO       "; word_len_o = 4'd5 ; end  // FACIL   FUEGO
            6'd44 : begin word_data_o = "AGUA        "; word_len_o = 4'd4 ; end  // FACIL   AGUA
            6'd45 : begin word_data_o = "VERDE       "; word_len_o = 4'd5 ; end  // FACIL   VERDE
            6'd46 : begin word_data_o = "ROJO        "; word_len_o = 4'd4 ; end  // FACIL   ROJO
            6'd47 : begin word_data_o = "AZUL        "; word_len_o = 4'd4 ; end  // FACIL   AZUL
            6'd48 : begin word_data_o = "NEGRO       "; word_len_o = 4'd5 ; end  // FACIL   NEGRO
            6'd49 : begin word_data_o = "CINCO       "; word_len_o = 4'd5 ; end  // FACIL   CINCO
            6'd50 : begin word_data_o = "TRES        "; word_len_o = 4'd4 ; end  // FACIL   TRES
            6'd51 : begin word_data_o = "SIETE       "; word_len_o = 4'd5 ; end  // FACIL   SIETE
            6'd52 : begin word_data_o = "OCHO        "; word_len_o = 4'd4 ; end  // FACIL   OCHO
            6'd53 : begin word_data_o = "NUEVE       "; word_len_o = 4'd5 ; end  // FACIL   NUEVE
            6'd54 : begin word_data_o = "LAPIZ       "; word_len_o = 4'd5 ; end  // FACIL   LAPIZ
            6'd55 : begin word_data_o = "PAPEL       "; word_len_o = 4'd5 ; end  // FACIL   PAPEL
            6'd56 : begin word_data_o = "CABLE       "; word_len_o = 4'd5 ; end  // FACIL   CABLE
            6'd57 : begin word_data_o = "DATOS       "; word_len_o = 4'd5 ; end  // FACIL   DATOS
            6'd58 : begin word_data_o = "RELOJ       "; word_len_o = 4'd5 ; end  // FACIL   RELOJ
            6'd59 : begin word_data_o = "CHIP        "; word_len_o = 4'd4 ; end  // FACIL   CHIP
            6'd60 : begin word_data_o = "PUNTO       "; word_len_o = 4'd5 ; end  // FACIL   PUNTO
            6'd61 : begin word_data_o = "CAMPO       "; word_len_o = 4'd5 ; end  // FACIL   CAMPO
            6'd62 : begin word_data_o = "PLAYA       "; word_len_o = 4'd5 ; end  // FACIL   PLAYA
            6'd63 : begin word_data_o = "BARCO       "; word_len_o = 4'd5 ; end  // FACIL   BARCO
            default: begin word_data_o = "            "; word_len_o = 4'd0;  end
        endcase
    end

endmodule
