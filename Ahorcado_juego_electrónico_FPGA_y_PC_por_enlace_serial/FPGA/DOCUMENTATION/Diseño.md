# Ahorcado FPGA/PC — Diseño

Notas de diseño del proyecto: qué hace el sistema, cómo está partido y por qué
elegimos cada cosa donde había más de una opción razonable.

---

## 1. El sistema

La FPGA lleva todo el juego. La PC solo es una terminal: manda la letra que el
jugador escribe y muestra lo que la FPGA responde.

| | Fácil | Difícil |
|---|---|---|
| Palabras | cualquiera del banco | solo de 6 letras o más |
| Tiempo | 60 s | 45 s |

Seis errores como máximo. Las letras repetidas se ignoran sin penalizar. Al
terminar, el resultado se muestra 3 segundos y el sistema vuelve solo a la
pantalla de selección.

---

## 2. Arquitectura

```
top
├── clk_tick_gen          tick de 1 ms
├── button_input ×3       sincronizador, debounce, detector de flanco
├── game_controller       FSM y datapath del juego
├── word_rom              64 palabras
├── lfsr                  generador de 8 bits
├── round_timer           cuenta regresiva
├── lcd_screen_ctrl  →  lcd_peripheral  →  lcd_controller  →  PmodCLP
│    ├── lcd_screen_snapshot  copia estable de los datos de la partida
│    ├── lcd_step_decoder     del número de paso a comando, fila y columna
│    └── lcd_text_gen         el byte que va en cada posición
├── uart_msg         →  uart_peripheral →  uart_core       →  PC
├── uart_test_block       pruebas del UART, se activa por parámetro
├── display_controller
├── buzzer_controller
└── led_controller
```

**Por qué hay dos módulos de presentación.** Mostrar una pantalla en el LCD son
unas 34 transacciones, cada una con su `start`, su espera de `busy` y su `done`.
Notificar una letra por UART son unos 34 bytes, cada uno esperando a que `send`
vuelva a cero. Si eso lo hiciera el `game_controller`, la FSM pasaría de 7
estados a varias decenas y mezclaría las reglas del juego con el armado de texto.

Con `lcd_screen_ctrl` y `uart_msg` aparte, el `game_controller` solo conoce
reglas: recibe una letra, decide qué pasa, y dispara un evento. Cada capa se
prueba por separado.

`lcd_screen_ctrl` recibe qué pantalla mostrar más los datos del juego (palabra,
patrón revelado, errores, modo, victorias) y devuelve `busy`. `uart_msg`
recibe un evento —inicio, letra, repetida, fin— y los mismos datos, y arma la
trama.

**Cada periférico tiene un solo maestro**, que es su capa de presentación. Por
eso `uart_msg` también se encarga de la recepción: leer la letra del jugador
obliga a sondear `new_rx`, leer el registro RX y escribir el bit que lo limpia,
todo sobre el mismo bus por el que salen las tramas. Si el `game_controller`
leyera por su cuenta habría dos módulos manejando el mismo periférico, con una
trama saliendo y una letra entrando a la vez. El `game_controller` no toca
ningún bus: pide pantallas y eventos, y recibe letras ya validadas.

---

## 3. Reloj y temporización

Un solo reloj de 100 MHz. Sin relojes derivados: todo sale de contadores y clock
enables.

```
100 000 000 ciclos/s ÷ 1000 = 100 000 ciclos por milisegundo
```

Ese tick de 1 ms alimenta el temporizador, el debounce, el multiplexado de
displays y la pantalla de resultado. Lo que necesita más resolución —el buzzer,
el LCD, los baudios— lleva su propio contador desde el mismo reloj.

Ningún módulo tiene números de ciclos escritos por dentro. Todo son parámetros
que bajan desde el top:

| Parámetro | Valor | Ciclos o ticks | Cuenta |
|---|---:|---:|---|
| `TICK_1MS_CYCLES` | 1 ms | 100 000 | 100e6 / 1000 |
| `DEBOUNCE_MS` | 10 ms | 10 ticks | |
| `T_EASY_S` | 60 s | 60 000 ticks | |
| `T_HARD_S` | 45 s | 45 000 ticks | |
| `RESULT_MS` | 3 s | 3 000 ticks | |
| `MUX_DIGIT_MS` | 1 ms | 1 tick | 4 dígitos → 250 Hz |
| `BAUD_DIV` | 115 200 baud | 868 | 100e6/115200 = 868.06, error 0.006 % |
| `LCD_POWERON_MS` | 50 ms | 50 ticks | el manual pide 20, damos margen |
| `LCD_SHORT_US` | 60 µs | 6 000 | el manual pide 37 |
| `LCD_LONG_US` | 2 ms | 200 000 | el manual pide 1.52 |
| `LCD_SETUP_CYC` | 200 ns | 20 | elegido por nosotros, ver sección 9 |
| `LCD_E_HIGH_CYC` | 1 µs | 100 | ídem |
| `LCD_E_LOW_CYC` | 1 µs | 100 | ídem |

Buzzer, semiperiodos: 2 kHz → 25 000 · 2.5 kHz → 20 000 · 3 kHz → 16 667 ·
800 Hz → 62 500 · 500 Hz → 100 000.

**Por qué parametrizado y no constantes.** La simulación post-implementación
temporizada es obligatoria, y con los valores reales habría que simular 50 ms de
arranque del LCD más un byte completo de UART antes de poder validar una sola
letra. Con back-annotation eso no termina nunca. Generamos una variante con las
constantes reducidas (`SIM_FAST`) para esa simulación, y el bitstream de la
tarjeta usa los valores reales. Meter los parámetros después habría obligado a
tocar todos los módulos y todos los testbenches.

---

## 4. Reset y arranque

`rst_i` es síncrono, activo en alto, y viene de `BTN_RST` después de
sincronizarlo y filtrarlo. Deja el sistema en la pantalla de selección con
victorias en 00, errores en 0, bitmask vacío y temporizadores en cero, y pide un
redibujado.

Pero el botón no puede ser el único arranque: si lo fuera, al programar la FPGA
la pantalla se quedaría en blanco hasta que alguien lo pulsara. Así que:

- todos los registros declaran su valor inicial en la declaración, y en Xilinx
  esos valores se cargan desde el bitstream durante la configuración;
- el `lcd_controller` arranca su secuencia de inicialización solo, con su propio
  contador, sin depender de `rst_i`.

El reset del juego no repite la inicialización física del LCD. No hace falta y
costaría 50 ms.

---

## 5. Botones

```
pin → sincronizador de 2 etapas → debounce 10 ms → detector de flanco → FSM
```

Nada asíncrono entra directo a la FSM. La línea RX del UART también pasa por dos
etapas.

| Señal | Botón | Pin |
|---|---|---|
| `BTN_RST` | central, `btnC` | E16 |
| `BTN_SEL` | izquierdo, `btnL` | T16 |
| `BTN_OK` | derecho, `btnR` | R10 |

`btnCpuReset` (C12) es un botón distinto, con polaridad contraria. No lo
usamos.

---

## 6. Banco de palabras

64 palabras en español, de 4 a 11 letras, sin tildes y sin Ñ. Cada una ocupa 12
caracteres ASCII con relleno de espacios, más un campo de longitud.

La ROM está ordenada por dificultad:

```
índices  0 .. 31  →  6 letras o más
índices 32 .. 63  →  4 o 5 letras
```

De ese orden depende la selección de la sección 7.

`rtl/word_rom.sv` se genera con `python/gen_word_rom.py`, que valida que haya 64
palabras distintas, que el rango bajo sea todo de 6 o más, que el alto sea de 4 o
5, que no haya caracteres fuera de A-Z y que ninguna pase de 12.

Lo generamos con script porque el orden es frágil: basta que alguien meta una
palabra corta entre las primeras 32 para que el modo difícil deje de cumplir, y
el fallo sería silencioso. Así queda comprobado cada vez.

La lectura es combinacional y se captura en un registro al empezar la partida.
Con 64 entradas de 100 bits, Vivado infiere ROM distribuida en LUTs; capturar en
registro separa ese camino de la lógica de comparación de letras.

---

## 7. Selección de la palabra

LFSR de 8 bits, 255 estados no nulos.

```
x⁸ + x⁶ + x⁵ + x⁴ + 1        taps 8, 6, 5, 4
semilla 8'b0000_0001
```

```systemverilog
lfsr_q <= {lfsr_q[6:0], lfsr_q[7] ^ lfsr_q[5] ^ lfsr_q[4] ^ lfsr_q[3]};
```

Corre libre: avanza en cada ciclo desde que sale del reset, pase lo que pase en
el juego. El valor se captura en el ciclo en que se detecta `BTN_OK`.

Si solo avanzara al empezar la partida, la secuencia de palabras sería idéntica
después de cada encendido, y eso es difícil de sostener como selección
pseudoaleatoria en la demostración. Corriendo libre, la variedad sale de cuándo
alguien pulsa el botón: unas décimas de segundo son millones de ciclos. En
simulación sigue siendo determinista, porque el testbench decide el ciclo exacto
de la pulsación.

El índice sale por truncamiento directo:

```
difícil:  rom_index = lfsr_capturado[4:0]     →  0 .. 31
fácil:    rom_index = lfsr_capturado[5:0]     →  0 .. 63
```

Un ciclo, sin módulo, sin rechazo, sin bucles. En modo difícil no puede salir
una palabra corta porque en el rango 0–31 no hay ninguna.

Queda un sesgo, y conviene decirlo con los números correctos. Como el estado
`8'h00` no existe, el índice 0 sale menos veces que los demás a lo largo del
ciclo de 255 estados:

| Modo | Índice 0 | Los demás | Desviación del índice 0 |
|---|---:|---:|---:|
| Difícil | 7 de 255 | 8 de 255 | −12 % |
| Fácil | 3 de 255 | 4 de 255 | −25 % |

En la práctica significa que la primera palabra del banco aparece algo menos que
las otras: un 1,18 % de las partidas en modo fácil en vez del 1,56 % que
correspondería. No afecta al juego, pero decir "un 0,4 % de sesgo" sería
inexacto: ese 0,4 % es la desviación de los otros 63 índices, no la del 0.

El testbench comprueba que el LFSR recorra 255 estados distintos, que nunca pase
por cero y que los 255 den una palabra de 6 letras o más en modo difícil.

---

## 8. Reglas de la partida

```
DIBUJA_SEL → SELECCION ─BTN_OK→ CARGA → INICIO → ESPERA_INICIO
                  ↑                                     ↓
                  │                                  JUGANDO ⇄ EVALUA
                  │                                     │        ↓
                  │                                     │     PUBLICA
                  │                                     │        ↓
                  │                                     └─ ESPERA_JUGADA
                  │                                              ↓
            RESULTADO ← ESPERA_FIN ← FIN ← desenlace ← ───────────┘
              (3 s)                          WIN / LER / LTO
```

`BTN_SEL` en `SELECCION` cambia el modo y vuelve a `DIBUJA_SEL`.

Los estados de espera están porque las dos capas de presentación tardan
milisegundos: no se puede pedir nada nuevo mientras alguna sigue ocupada.

**Un solo estado de fin, no tres.** Ganar, perder por fallos y perder por tiempo
hacen lo mismo: pintar, notificar, sonar y esperar. Lo único que cambia es un
código de dos bits, y ese código es justo lo que las dos capas reciben como
entrada. Tres estados que solo se diferencian en un dato pertenecen al camino de
datos, no al control. La diferencia sigue viéndose donde importa: el LCD muestra
`GANASTE`, `PERDISTE: FALLOS` o `PERDISTE: TIEMPO`, la PC recibe `WIN`, `LER` o
`LTO`, y el sonido de victoria no es el de derrota.

**`CARGA` va aparte de `INICIO`** porque las capas copian los datos en el mismo
flanco en que aceptan la orden. Registrar la palabra y disparar el dibujo en el
mismo estado haría que copiaran los valores viejos.

**El temporizador no se detiene mientras se publica.** Notificar una jugada tarda
unos milisegundos; pararlo en cada letra le regalaría tiempo al jugador y el
límite dejaría de ser el que dice el modo.

**Letras usadas:** bitmask de 26 bits, `índice = byte - 8'h41`. Si el bit ya está
puesto, la letra es repetida: no consume intento, no toca errores, no reinicia el
temporizador y no se vuelve a evaluar. Sí se avisa a la PC, para que el jugador
entienda por qué no pasó nada.

**Evaluación:** la letra se compara en paralelo contra todas las posiciones
menores que la longitud, se revelan todas las coincidencias a la vez, y si no hay
ninguna sube el contador de errores.

**Victoria:** `revealed == valid_mask`, evaluado ya con la letra en curso. Si la
última que faltaba llega correcta, se gana en ese mismo procesamiento.

**Errores:** contador ascendente de 0 a 6. Hacia afuera se informa lo que queda
(`6 - errores`), y esa resta se hace solo en la capa de presentación.

**Prioridad** cuando coinciden varias condiciones en el mismo ciclo:

```
victoria → sexto error → timeout
```

El sexto error pierde aunque quede tiempo. La victoria va primero porque una
letra que completa la palabra no puede ser a la vez un fallo.

**Timeout diferido.** Si el temporizador llega a cero mientras hay una
transacción del LCD o una trama UART a medias, se captura un flag y se atiende
cuando las dos capas quedan libres. Cortar a mitad dejaría media pantalla escrita
o una trama truncada que rompería el parser de Python. El instante lógico del
timeout es el de la captura, así que el retardo de unos milisegundos no cambia el
resultado.

**Contador de victorias:** BCD de dos dígitos, sube una unidad solo al ganar,
satura en 99 y se mantiene hasta el siguiente reset.

---

## 9. LCD

PmodCLP 16×2 con controlador Samsung KS0066, compatible HD44780, interfaz
paralela de 8 bits.

### Registros

**CONTROL/ESTADO (0x00)**

| Bit | Campo | Comportamiento |
|---:|---|---|
| 0 | `start` | lanza una transacción; se limpia al aceptarse |
| 1 | `rs` | 0 comando, 1 dato |
| 2 | `clear` | limpia pantalla |
| 3 | `home` | cursor al inicio sin borrar |
| 8 | `busy` | 1 mientras hay una operación en curso |
| 9 | `done` | 1 al terminar, hasta que se acepta otra operación |

**DATOS (0x04):** el byte en los bits 7:0.

`done` es un flag que se queda puesto, no un pulso de un ciclo. Con un pulso, el
maestro que sondea el registro podría no verlo nunca y quedarse esperando para
siempre.

Si una escritura activa varias solicitudes a la vez, la prioridad es
`clear > home > start`. Lo que llegue con `busy` en 1 se descarta; esperar es
tarea de `lcd_screen_ctrl`.

### R/W atado a cero

No leemos el busy flag del LCD. Hacerlo obligaría a declarar `DB[7:0]` como
`inout` con buffers triestado sobre pines Pmod, con control de dirección y riesgo
de contención, y todo para ahorrar microsegundos que aquí no significan nada. Con
`R/W = 0` todas las señales son salidas puras y esperamos por contador.

El `busy` del registro sigue existiendo: es el del periférico, no el del LCD.

### Tiempos

Del manual del PmodCLP: 20 ms tras encender antes del `Function Set`, 37 µs entre
instrucciones cortas, 1.52 ms tras `Clear Display`. Usamos 50 ms, 60 µs y 2 ms.

Secuencia de arranque:

```
encender → 50 ms
Function Set   (8 bits, 2 líneas, 5×8)  → 60 µs
Display On/Off (display sí, cursor no)  → 60 µs
Clear Display                           → 2 ms
Entry Mode Set (incremento, sin shift)  → listo
```

El manual no dice el ancho del pulso de `E` ni los setup y hold de RS y datos, y
no tenemos el datasheet del KS0066. Esos tres los fijamos nosotros con margen
amplio: 200 ns de setup, 1 µs de `E` en alto y 1 µs en bajo. El ciclo resultante,
2.2 µs, queda muy por debajo de los 60 µs entre operaciones. Van declarados como
elección nuestra, no como dato de hoja de datos, y se validan en la tarjeta.

El dato entra al controlador en el flanco de bajada de `E`.

### Pantallas

Las líneas se escriben completas, rellenando con espacios hasta 16. Así no quedan
restos de la pantalla anterior y no hace falta un `clear` antes de cada
redibujado, que es lo que produce parpadeo.

```
Columna:  0123456789012345

Selección:
Línea 0: "AHORCADO  V:nn  "
Línea 1: "MODO: FACIL     "   o   "MODO: DIFICIL   "

Partida:
Línea 0: "A______         "     patrón, resto espacios
Línea 1: "INTENTOS: 6    F"     intentos que quedan y modo

Resultado:
Línea 0: "   GANASTE!     "
Línea 0: "PERDISTE: FALLOS"
Línea 0: "PERDISTE: TIEMPO"
Línea 1: "TECLADO         "     la palabra
```

Direcciones DDRAM: fila 0 en 0x00 (comando 0x80), fila 1 en 0x40 (comando 0xC0).

Se redibuja solo cuando cambia algo visible: al entrar a selección, al cambiar de
modo, al empezar la partida, al evaluar una letra que mueve el patrón o los
intentos, al entrar al resultado y al subir el contador de victorias. Nunca en
bucle: refrescar continuamente parpadea y dejaría `busy` activo casi siempre.

Un redibujado completo son 2 comandos más 32 caracteres, unos 2 ms.

Los 3 segundos del resultado se cuentan desde que termina el redibujado, no desde
que se entra al estado, para que se vean 3 segundos completos.

### Cómo está partida la capa de presentación

`lcd_screen_ctrl` empezó siendo un único módulo que hacía cuatro cosas a la vez:
copiar los datos de la partida, llevar la cuenta del paso, decidir qué carácter
toca en cada posición y dialogar con el periférico. Funcionaba, pero costaba
seguirlo y cualquier cambio en los textos obligaba a leer también la máquina de
estados.

Ahora esas responsabilidades están en cuatro archivos:

| Módulo | De qué se encarga | Tipo |
|---|---|---|
| `lcd_screen_ctrl` | la máquina de estados que habla con el periférico y el contador de paso | secuencial |
| `lcd_screen_snapshot` | registra los datos de la partida al aceptar la orden | secuencial |
| `lcd_step_decoder` | traduce el número de paso a comando, fila y columna | combinacional |
| `lcd_text_gen` | arma el byte que va en esa fila y columna | combinacional |

Las constantes que comparten viven en `lcd_screen_pkg`: los códigos de pantalla,
el mapa de registros del periférico y el ancho de la pantalla.

El reparto deja cada pieza con una sola razón para cambiar. Los textos se editan
en `lcd_text_gen` sin abrir la máquina de estados; la aritmética del paso se
comprueba leyendo doce líneas; y el diálogo con el periférico queda reducido a
cinco estados sin nada de armado de texto en medio.

La interfaz externa no cambió: `top` instancia `lcd_screen_ctrl` con los mismos
puertos que antes, y ni el periférico ni el `game_controller` notan la
diferencia.

**Una consecuencia práctica del paquete.** iverilog compila en el orden en que se
le pasan los archivos y necesita el paquete antes que cualquier módulo que lo
importe. Por orden alfabético `lcd_screen_ctrl.sv` cae antes de
`lcd_screen_pkg.sv`, así que `run_tests.py` pone los paquetes al principio de la
lista a propósito. Vivado resuelve esa dependencia por su cuenta, pero el
paquete tiene que estar agregado al proyecto.

---

## 10. UART

115200 baudios. `100e6 / 115200 = 868.06`, así que el divisor es 868 y el error
queda en 0.006 %.

| `addr_i` | Registro |
|---|---|
| `2'b00` | datos TX |
| `2'b01` | datos RX |
| `2'b10` | control |

`rdata_o` es combinacional, un multiplexor sobre `addr_i` con `default` explícito
para que no se infiera un latch. Así el maestro puede mirar `busy`, `done`,
`send` y `new_rx` en el mismo ciclo en que pone la dirección.

### El registro de control no es plano

Hay que limpiar `new_rx` escribiendo el registro, pero una escritura de 32 bits
toca `send` y `new_rx` a la vez. Si el registro fuera plano, limpiar `new_rx`
podría cancelar una transmisión en curso, y lanzar una transmisión podría borrar
un `new_rx` recién llegado y perder la letra del jugador. Es una carrera real, y
de las que se manifiestan como fallo intermitente justo el día de la
presentación.

| Bit | Campo | Escribir 1 | Escribir 0 | Leer |
|---:|---|---|---|---|
| 0 | `send` | arranca la transmisión si no hay otra | nada | 1 mientras transmite |
| 1 | `new_rx` | limpia el flag | nada | 1 si hay byte sin leer |

Con `send` que solo se puede poner y `new_rx` que se limpia escribiendo un uno,
los dos campos son independientes.

### El núcleo

El profesor entregó un núcleo TX/RX en VHDL (`UART.vhd`, `UART_tx.vhd`,
`UART_rx.vhd`) y pidió envolverlo en SystemVerilog. Los tres archivos están en
`FPGA/DESIGN` tal como llegaron, sin modificar. La envoltura es
`DESIGN/uart_core.sv` y es la capa de adaptación que habíamos previsto: todo lo
que dependía del núcleo real queda ahí, y ni los registros ni nada por encima
cambiaron.

**No instanciamos `UART.vhd`.** Ese archivo solo cablea el transmisor con el
receptor, pero no expone los genéricos de la velocidad, así que sus componentes
se quedarían con los valores por omisión, que están calculados para un reloj de
16 MHz. Instanciamos `UART_tx` y `UART_rx` directamente para poder pasarles los
valores de 100 MHz. Se conserva el archivo en el repositorio aunque no se use.

**Velocidad.** El transmisor cuenta ciclos de reloj por bit; el receptor
sobremuestrea por 16, así que su genérico es dieciseisavo:

| | Cálculo | Valor | Error |
|---|---|---:|---:|
| `BAUD_CLK_TICKS` (TX) | 100e6 / 115200 = 868.06 | 868 | −0.006 % |
| `BAUD_X16_CLK_TICKS` (RX) | (100e6 / 115200) / 16 = 54.25 | 54 | −0.47 % |

El −0.47 % del receptor se acumula dentro de la trama. El receptor muestrea el
bit *k* a 1.5 + *k* tiempos de bit del flanco de arranque, así que en el último
bit el desfase es 3.97 % de un bit. Sumando los 0.54 µs con que puede tardar en
detectarse el flanco de arranque, otro 6.22 %, el peor caso queda en 10.2 % de
un bit frente al 50 % disponible hasta el borde. Entra con holgura, pero era
justo lo que habíamos anotado que había que mirar.

**Dos cosas del núcleo que no coincidían con lo que habíamos supuesto.**

`tx_rdy` no es una señal de listo pese al nombre: es un pulso de un ciclo al
terminar cada byte. El periférico necesita un nivel de ocupado, y eso lo produce
la envoltura entre la petición y ese pulso.

Y el núcleo ignora `tx_start` durante casi un tiempo de bit después de terminar
un byte, mientras mantiene alto su propio `start_reset`. Un pulso de un ciclo
que caiga en esa ventana se pierde sin dejar rastro y el sistema se queda
esperando para siempre. Por eso la envoltura convierte la petición en un nivel
que se mantiene hasta que el núcleo confirma el fin: en cuanto la ventana se
cierra, la toma. El efecto secundario es que entre dos bytes seguidos la línea
queda en reposo unos tres tiempos de bit en vez de uno, lo que es válido en
cualquier receptor y lleva el mensaje más largo de 3.0 ms a unos 4.0 ms.

**Simulación.** iverilog no compila VHDL, así que la regresión sigue corriendo
contra el modelo de comportamiento, con `SIMULATION/uart_core_sim.sv`
declarando el mismo módulo. El núcleo real se simula en Vivado, que sí entiende
lenguaje mixto, con las mismas pruebas: ahí es donde se comprueba que la
interfaz supuesta y la real coinciden.

Los dos archivos declaran `uart_core` y nunca se compilan juntos.
`SIMULATION/run_tests.py` arma la lista de fuentes excluyendo el que no toca.

### Bloque de pruebas

`uart_test_block` es un módulo aparte, sintetizable, que se activa por parámetro
del top. Manda en ciclo la secuencia A–Z seguida de salto de línea, hace eco de
lo que reciba y muestra el último byte recibido en los LEDs. Sirve para validar
el periférico contra la PC antes de integrar el juego.

---

## 11. Protocolo

Texto ASCII terminado en salto de línea, con campos de ancho fijo.

**De la PC a la FPGA:** un byte, de la `A` a la `Z`. Cualquier otra cosa se
descarta. Python valida antes de mandar, y la FPGA valida igual.

Ese filtro vive en `uart_msg`, no en el `game_controller`: descartar un byte que
no es una letra es cuestión de protocolo, no una regla del juego. El aviso de
byte recibido se limpia siempre, sea la letra válida o no. Eso resuelve además lo
que pide el enunciado sobre las letras que llegan en la pantalla de selección o
mostrando el resultado: se ignoran, pero el aviso queda limpio y no se cuela como
primera letra de la partida siguiente.

**De la FPGA a la PC:**

| Mensaje | Formato | Cuándo |
|---|---|---|
| Inicio | `START:<M>:<LL>` | al empezar la partida |
| Patrón | `PATT:<p>` | al empezar y tras cada letra |
| Letra | `LET:<X>:<R>` | al evaluar una letra |
| Intentos | `ERR:<n>` | al empezar y tras cada letra |
| Fin | `END:<E>:<W>` | al terminar |

`<M>` es `F` o `D`. `<LL>` es la longitud con dos dígitos. `<p>` es el patrón con
guiones bajos en lo oculto. `<R>` es `OK `, `NO ` o `RPT`, siempre tres
caracteres. `<n>` son los intentos que quedan. `<E>` es `WIN`, `LER` por errores
o `LTO` por tiempo. `<W>` es la palabra completa.

```
al empezar     START:F:07    PATT:_______    ERR:6
letra buena    LET:A:OK      PATT:A______    ERR:6
letra mala     LET:Z:NO      PATT:A______    ERR:5
repetida       LET:A:RPT
al terminar    END:WIN:ARBOLES
```

Ancho fijo porque simplifica las dos puntas: en RTL solo el patrón y la palabra
tienen longitud variable, y en Python el parser trocea por posición sin
expresiones regulares. La secuencia más larga son unos 34 bytes, 3 ms a 115200,
frente al segundo de resolución del juego.

La palabra va en el mensaje de fin porque es lo clásico del ahorcado y no filtra
nada durante la partida.

El tiempo restante no se manda: se ve en los displays.

**Control de flujo.** Solo hay un registro de recepción y ningún FIFO, así que un
byte que llegue con `new_rx` todavía en 1 se pierde. La aplicación de PC no
habilita la siguiente letra hasta recibir la línea que cierra la anterior
(`ERR:`, `LET:...:RPT` o `END:`). La FPGA no depende de que la PC cumpla: si
llega un byte de más lo descarta y la partida sigue igual. El juego es alternado
por naturaleza, así que un FIFO no añadiría nada; lo dejamos anotado como
limitación conocida.

---

## 12. Displays, LEDs y sonido

Cuatro de los ocho dígitos, con la misma distribución siempre:

```
AN3–AN2  →  segundos que quedan
AN1–AN0  →  victorias
```

`AN7–AN4` se mantienen apagados explícitamente.

Multiplexado a un dígito por tick de 1 ms: refresco completo cada 4 ms, 250 Hz,
muy por encima del umbral de parpadeo y sin contadores nuevos.

**LEDs:** LED0 en selección, LED1 en partida, LED2 en resultado, LED15 encendido
si el modo es difícil. Los tres primeros son excluyentes y lo comprobamos con una
assertion. Con un solo LED habría que codificar por parpadeo, que a simple vista
no se distingue.

**Sonido:**

| Evento | Tono | Duración |
|---|---|---:|
| Letra correcta | 2 kHz | 100 ms |
| Letra incorrecta | 500 Hz | 150 ms |
| Victoria | 2 → 2.5 → 3 kHz | 150 ms cada uno |
| Derrota | 800 → 500 Hz | 200 ms cada uno |

Si suena algo y llega otro evento, el nuevo se descarta, salvo que sea de fin de
partida: ese corta lo que esté sonando, porque es el que importa.

La Nexys 4 no tiene buzzer. Lo que tiene es una salida de audio mono que va a un
filtro paso bajo y sale por el jack de 3.5 mm, con `AUD_PWM` en A11. Esto
significa que **hay que llevar audífonos o un parlante a la presentación**.

Cómo se maneja esa salida está sin cerrar: ver la sección 15.

Si en el aula no se oye, queda libre la fila de arriba de JB (JB1–JB4) para
un Pmod buzzer, además de los conectores JC y JD enteros.

---

## 13. Aplicación de PC

`PYTHON/DESIGN/ahorcado_terminal.py`. Pide una letra, valida que sea un solo
carácter de la A a la Z, la pasa a mayúscula y la manda como un byte. Trocea los
mensajes por posición —para eso son de ancho fijo— y muestra el patrón, los
intentos que quedan, cómo fue la última letra y el resultado final. Una línea que
no encaje se reporta y se descarta, sin detener nada.

No guarda la palabra secreta, no elige la palabra, no decide quién gana y no
lleva el tiempo. Todo eso está en la FPGA.

**Por qué hay un hilo lector.** El límite de tiempo corre en la FPGA, así que la
partida puede terminar mientras la terminal está esperando que el jugador
escriba. Leyendo de forma sincrónica ese aviso no aparecería hasta que escribiera
algo, que es justo cuando ya no sirve. Con el hilo lector el aviso sale en el
momento, y la letra que el jugador teclee después se descarta en vez de contarse
en la partida siguiente.

**Ni tildes ni Ñ.** El banco no las tiene y la FPGA solo acepta A–Z, así que la
terminal las rechaza con un mensaje propio en lugar de mandar un byte que se
descartaría en silencio. Tampoco hay atajos de una sola letra para cerrar: la Q
es una letra del banco y el jugador tiene que poder intentarla.

El modo y el comienzo de la partida se eligen en la tarjeta. La terminal espera a
que la FPGA anuncie el inicio.

---

## 14. Pines

| Función | Puerto | Dónde | Pin |
|---|---|---|---|
| Reloj | `clk_i` | | E3 |
| LCD `DB[3:0]` | `lcd_db_o[3:0]` | JA1–JA4 | B13, F14, D17, E17 |
| LCD `DB[7:4]` | `lcd_db_o[7:4]` | JA7–JA10 | G13, C17, D18, E18 |
| LCD `RS` | `lcd_rs_o` | JB7 | K16 |
| LCD `R/W` | `lcd_rw_o` | JB8 | R16 |
| LCD `E` | `lcd_e_o` | JB9 | T9 |
| Audio | `aud_pwm_o` | AUD_PWM | A11 |
| Habilitación de audio | `aud_sd_o` | AUD_SD | D12 · *sin confirmar, ver sección 15* |
| `BTN_RST` | `btn_rst_i` | btnC | E16 |
| `BTN_SEL` | `btn_sel_i` | btnL | T16 |
| `BTN_OK` | `btn_ok_i` | btnR | R10 |
| UART RX | `uart_rx_i` | RsRx | C4 |
| UART TX | `uart_tx_o` | RsTx | D4 |
| Segmentos | `seg_o[6:0]` | CA–CG | L3, N1, L5, L4, K3, M2, L6 |
| Ánodos | `an_o[7:0]` | AN0–AN7 | N6, M6, M3, N5, N2, N4, L1, M1 |
| LEDs de estado | `led_o[2:0]` | LED0–LED2 | T8, V9, R8 |
| LED de modo | `led_o[15]` | LED15 | P2 |

El PmodCLP ocupa el conector JA completo más la fila de abajo de JB, porque J1
lleva los ocho bits de datos y J2 las tres señales de control. La fila de abajo
no es una preferencia: montando la tarjeta se comprobó que, con J1 metido en el
JA, el J2 no alcanza la fila de arriba. La revisión B funciona a 3.3 V, que es
lo que dan los Pmod.

Todo con `IOSTANDARD LVCMOS33`. El XDC está en
`constraints/nexys4_ahorcado.xdc`, con el `create_clock` de 10 ns.

---

## 15. Polaridades y cosas por verificar

Las polaridades salen del manual de referencia de la Nexys 4:

| Señal | Nivel activo | Lo que dice el manual |
|---|---|---|
| Pulsadores BTNC/U/D/L/R | alto | "normally generate a low output when they are at rest, and a high output only when they are pressed" |
| CPU_RESET | **bajo** | "generates a high output when at rest and a low output when pressed" |
| LEDs | alto | conectados por ánodo con resistencia de 330 Ω, "turn on when a logic high voltage is applied" |
| Segmentos CA–CG | bajo | ánodo común, pero los habilitadores están invertidos por transistores |
| Ánodos AN0–AN7 | bajo | "both the AN0..7 and the CA..G/DP signals are driven low when active" |

Los dejamos igualmente como parámetros del top, porque cuesta cero y deja el
ajuste en un solo sitio si alguna vez cambiamos de tarjeta:

```systemverilog
parameter logic BTN_ACTIVE_LEVEL = 1'b1;
parameter logic LED_ACTIVE_LEVEL = 1'b1;
parameter logic SEG_ACTIVE_LEVEL = 1'b0;
parameter logic AN_ACTIVE_LEVEL  = 1'b0;
```

La polaridad invertida de CPU_RESET confirma que hay que dejarlo en paz: nuestro
reset es `btnC`, que es activo en alto como los demás pulsadores.

### La salida de audio no está resuelta

El manual de la Nexys 4 documenta `AUD_PWM` en A11 como entrada del filtro paso
bajo, pero **no menciona `AUD_SD` en ninguna parte**, aunque el pin aparezca en
el XDC de Digilent. Tampoco lo documenta el manual de la Nexys 4 DDR.

Y hay un detalle que puede hacer que no suene nada: el manual de la DDR describe
la entrada del filtro como colector abierto, "the signal needs to be driven low
for logic '0' and left in high-impedance for logic '1'". Si en nuestra tarjeta
pasa lo mismo, `aud_pwm_o` no puede ser una salida normal: habría que declararla
como triestado, poniendo `0` o alta impedancia en vez de `0` o `1`.

Las dos cosas hay que mirarlas en el esquemático de la tarjeta antes de escribir
el `buzzer_controller`. Si el tema se complica, el plan B del Pmod buzzer en
la fila de arriba de JB lo resuelve sin depender de nada de esto.

### Lo demás pendiente

| Qué | Por qué | Cómo se cierra |
|---|---|---|
| Interfaz del núcleo UART | todavía no lo tenemos | capa de adaptación + prueba de contraste al recibirlo |
| Trama del núcleo: paridad, bits de parada | depende del núcleo | al recibirlo |
| Ancho de `E` y setup/hold del LCD | el manual del PmodCLP no los da | validación en la tarjeta |
| Función y polaridad de `AUD_SD` | no aparece en el manual | esquemático de la tarjeta |
| Si `AUD_PWM` es colector abierto | el manual de la DDR dice que sí | esquemático de la tarjeta |
| Conexión del PmodCLP a JA y JB | deducida del pinout | comprobar antes de la primera prueba |
| Que el audio se oiga en el aula | depende del parlante | probarlo antes de la presentación |

---

## 16. Cómo lo vamos a probar

Cada módulo con lógica de verdad lleva su testbench, con estímulos deterministas,
comprobación automática y un resumen final de PASS/FAIL, no solo formas de onda
para mirar.

Primero módulos sueltos, después subsistemas, después integración y al final el
sistema completo. Verificando solo el conjunto, un fallo no dice en qué módulo
está.

Lo que hay que cubrir:

- reset, y arranque sin pulsar reset
- selección de modo, rebotes de los tres botones
- LFSR: 255 estados distintos, nunca el cero, reproducible
- selección: los 255 estados dan palabra de 6 o más en difícil
- ROM: 64 palabras, longitudes, orden, solo A-Z
- letra buena, mala, con varias coincidencias, y repetida de los dos tipos
- seis errores, victoria, timeout
- prioridad cuando coinciden
- timeout que cae mientras se envía una trama: la trama sale entera
- UART: TX, RX, y que `send` y `new_rx` no se pisen entre sí
- protocolo: trama exacta de cada evento, incluido `RPT` y la resta de intentos
- bytes inválidos, y bytes que llegan fuera de partida
- LCD: `busy` y `done`, rechazo con `busy` en 1, prioridad de solicitudes,
  inicialización completa
- temporizador, displays, multiplexado, victorias y su saturación
- buzzer y LEDs

Después de eso: síntesis sin latches ni múltiples drivers, implementación con
timing cerrado a 100 MHz, simulación post-implementación cubriendo la recepción y
validación de una letra, y prueba física.

### Estado actual

Hay dieciséis testbenches con resumen PASS/FAIL, y los dieciséis pasan. El RTL
compila sin un solo aviso bajo `verilator --lint-only -Wall`, tanto módulo por
módulo como el sistema completo.

Conviene decir con precisión qué cubre cada cosa, porque hay más módulos que
testbenches. Los tres módulos en que se partió la capa de presentación del LCD
—`lcd_screen_snapshot`, `lcd_step_decoder` y `lcd_text_gen`— no tienen testbench
propio: se verifican a través de `tb_lcd_screen_ctrl`, que compara los treinta y
dos caracteres de cada una de las seis pantallas, carácter por carácter, y por
tanto ejercita los tres de punta a punta. Dos de ellos son combinacionales puros
y el tercero es un banco de registros con una sola condición de carga, así que un
testbench propio repetiría lo que la prueba de nivel superior ya comprueba.

Al hacer ese reparto se comprobó además, con un `miter` y un solver SAT, que la
versión nueva de `lcd_screen_ctrl` y la anterior responden igual: no existe
ninguna secuencia de entradas, con cualquier combinación de `busy` y `done`, que
haga diferir sus salidas durante los primeros 25 ciclos. Esa comprobación alcanza
los primeros seis de los treinta y cuatro pasos; el recorrido completo de las
seis pantallas lo cubre el testbench, no la demostración formal.

La terminal de PC también tiene su prueba, con el mismo criterio y sin necesidad
de la tarjeta: `PYTHON/SIMULATION/test_terminal.py` juega una partida completa
contra un puerto serie falso que responde como respondería la FPGA, con la
entrada del jugador sustituida por un guion. Comprueba el troceo de las cinco
líneas del protocolo y de dos docenas de líneas rotas, el rechazo de entradas
inválidas, que por el puerto no salga nunca nada que no sea una letra, y que el
ruido en la línea no detenga la aplicación.

El de `top` es la prueba de integración: instancia el sistema completo, pulsa los
botones con el nivel mantenido lo suficiente para pasar el filtro de rebotes, y
observa únicamente las patas del módulo LCD y la línea serie. El monitor
reconstruye las dos filas del LCD siguiendo el cursor, de modo que lo que se
compara es el texto que vería el jugador, y decodifica la trama bit a bit
muestreando en el centro de cada bit, como haría Python. Cubre una partida:
selección, cambio de modo, comienzo, letra acertada, letra fallada, derrota por
seis fallos y vuelta sola a la selección.

Los tiempos van reducidos por parámetro en los testbenches —el tick, los
baudios, las esperas del LCD y la duración del resultado— porque con los valores
reales una sola pantalla son millones de ciclos. Los valores reales están
comprobados en el testbench de cada módulo, y esos mismos parámetros son los que
hacen viable la simulación post-implementación temporizada.

La regresión se corre con `python run_tests.py` desde `FPGA/SIMULATION`, o con
`--lint` para revisar además el RTL con verilator.

Falta correr las mismas pruebas en Vivado contra el núcleo real en VHDL y
comparar sus resultados con los del modelo. La integración con el núcleo real sí
está comprobada sobre la tarjeta, como se cuenta más abajo; lo que falta es la
comparación lado a lado en simulación, que es la que diría si el modelo y el
núcleo se comportan igual ante los mismos estímulos.

---

## 17. Resultados de síntesis e implementación

Vivado, dispositivo `xc7a100t` de la Nexys 4, reloj de 100 MHz declarado con
`create_clock -period 10.000`.

### Síntesis

| | |
|---|---|
| LUTs | 902 de 63 400 · 1,42 % |
| Registros | 632 de 126 800 · 0,50 % |
| **Registros inferidos como latch** | **0** |
| Errores | 0 |
| Avisos críticos | 0 |
| Avisos | 143 |

Que los 632 registros sean flip-flops y ninguno latch es la comprobación que
importa de toda la tabla: confirma que no quedó ningún `always_comb` con una rama
sin asignar.

Los 143 avisos son tres grupos, y los tres se esperan:

| Cantidad | Aviso | Motivo |
|---|---|---|
| 100 | `Synth 8-7129` | bits del bus de 32 bits que los periféricos no usan, porque la interfaz es de 32 bits por convenio y cada registro ocupa unos pocos |
| 12 | `Synth 8-3917` | LED 3 al 14 amarrados a cero: se restringen los dieciséis para que Vivado genere el bitstream, aunque el juego use cuatro |
| 3 | `Synth 8-3332` | la máquina de `uart_test_block` se elimina porque `MODO_PRUEBA_UART` está apagado |

### Implementación

| | |
|---|---|
| LUTs tras colocar | 887 · 1,40 % |
| Registros | 632 · 0,50 % |
| Pines | 50 de 210 · 23,81 % |
| WNS, holgura de establecimiento | **+1,813 ns** · 0 caminos fallando de 1430 |
| WHS, holgura de mantenimiento | **+0,134 ns** · 0 caminos fallando de 1430 |
| WPWS, ancho de pulso | +4,500 ns · 0 fallando de 633 |
| Ruteo | 1417 de 1417 conexiones, 0 errores |
| DRC y metodología | sin violaciones |
| Avisos de implementación | 0 |

El timing cierra con 1,813 ns de margen sobre un período de 10 ns. Dicho de otra
forma, el camino más lento tarda 8,187 ns, así que el diseño toleraría un reloj de
unos 122 MHz antes de empezar a fallar. La holgura de mantenimiento es positiva,
que es lo que hay que mirar para descartar problemas que no se arreglan bajando la
frecuencia.

El diseño ocupa menos del 1,5 % de la tarjeta. No hubo que pelear con recursos en
ningún momento, lo que era de esperar: el juego es sobre todo control, y la
memoria más grande es la ROM de 64 palabras.

### Bitstream

`write_bitstream` termina con 0 errores y 0 avisos, y el DRC previo con 0 errores.

---

## 18. Puesta en marcha y prueba física

El orden de abajo está pensado para que, si algo falla, el síntoma diga en qué
bloque está el problema, en vez de dejar todo el sistema como sospechoso.

**1. Antes de energizar.** J1 del PmodCLP al conector JA completo y J2 a la fila
de abajo del JB, comprobando la marca del pin 1 en los dos. Un Pmod corrido una
posición no produce ningún error visible: simplemente no funciona.

**2. Programar y mirar el LCD.** Si aparece la pantalla de selección, eso valida
de golpe el reloj, la secuencia de arranque del LCD, el periférico y la capa de
presentación. Si queda en blanco o con bloques negros, el problema es de
cableado y no hay que seguir.

**3. Probar sin la PC.** El botón izquierdo alterna Fácil y Difícil, con el LED 15
siguiendo el cambio; el derecho arranca la partida y enciende el LED 1; los
displays cuentan los segundos hacia atrás desde 60 o 45; el central reinicia.
Dejando vencer el tiempo sin tocar nada debe salir `PERDISTE: TIEMPO` durante tres
segundos y volver solo a la selección. Todo esto es independiente del enlace
serial.

**4. Conectar la terminal.** Con `python ahorcado_terminal.py --list` se localiza
el puerto y con `--port COMn` se abre. Al pulsar el botón derecho deben llegar las
líneas `START:`, `PATT:` y `ERR:`. Si el LCD arranca la partida pero por el serial
no llega nada, el problema queda acotado al camino UART.

Un detalle que cuesta un rato si no se sabe: Windows no comparte los puertos
serie. Si otro programa tiene el puerto abierto —una consola, el monitor serie de
otro entorno— la terminal falla con `Access is denied`. El Hardware Manager de
Vivado no estorba, porque la tarjeta expone el JTAG y el serial como interfaces
distintas del mismo cable.

**5. Jugar una partida completa,** comprobando los cuatro casos: letra correcta,
letra incorrecta, letra repetida y fin de partida, y que el LCD y la terminal
cuenten siempre lo mismo.

### Resultado

El sistema completo funciona sobre la tarjeta: se juega desde la terminal de
Python y el LCD, los displays y los LEDs acompañan. Con eso queda comprobada en
hardware la integración con el núcleo UART en VHDL, que es la parte que la
regresión con iverilog no puede cubrir porque sustituye el núcleo por un modelo.

Las fotografías de las tres pantallas, la captura de una partida en la terminal y
la del montaje están en `DOCUMENTATION/FIGURAS`.
