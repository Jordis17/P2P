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
├── uart_msg_tx      →  uart_peripheral →  uart_core       →  PC
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

Con `lcd_screen_ctrl` y `uart_msg_tx` aparte, el `game_controller` solo conoce
reglas: recibe una letra, decide qué pasa, y dispara un evento. Cada capa se
prueba por separado.

`lcd_screen_ctrl` recibe qué pantalla mostrar más los datos del juego (palabra,
patrón revelado, errores, modo, victorias) y devuelve `busy`. `uart_msg_tx`
recibe un evento —inicio, letra, repetida, fin— y los mismos datos, y arma la
trama.

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

Queda un sesgo mínimo: como el estado `8'h00` no existe, el patrón `000000` en
los seis bits bajos aparece 3 veces por ciclo y los otros 63 aparecen 4. Son
cuatro décimas de punto porcentual. Lo mencionamos en el informe en vez de
esconderlo.

El testbench comprueba que el LFSR recorra 255 estados distintos, que nunca pase
por cero y que los 255 den una palabra de 6 letras o más en modo difícil.

---

## 8. Reglas de la partida

```
MODE_SELECT ─BTN_OK→ START_GAME → PLAYING → WIN / LOSE_ERROR / LOSE_TIMEOUT
                                                      ↓
                                    MODE_SELECT ← RESULT (3 s)
```

Puede haber estados de espera mientras la capa de presentación está ocupada.

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

### El núcleo todavía no lo tenemos

No conocemos sus puertos ni su configuración de trama. Para no quedarnos parados
ni inventarnos una interfaz, `uart_peripheral` se diseña contra este supuesto:

```systemverilog
tx_data_o[7:0], tx_start_o, tx_busy_i
rx_data_i[7:0], rx_valid_i
```

y toda la dependencia queda en una capa de adaptación dentro del periférico. Si
el núcleo real es distinto, solo se toca esa capa: los registros, la semántica de
`send` y `new_rx`, `uart_msg_tx` y el `game_controller` no se enteran.

Para verificar mientras tanto usamos un modelo de comportamiento del núcleo y un
modelo de línea serie a 115200 que permite comprobar la trama bit a bit. Cuando
llegue el núcleo real, mismos estímulos con los dos y comparamos.

Si el núcleo usa sobremuestreo ×16 el divisor sería 54.25 → 54, con 0.47 % por
bit y 4.7 % acumulado en diez: dentro del margen pero sin holgura. Hay que
mirarlo.

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

Si en el aula no se oye, quedan libres JB7–JB10 para un Pmod buzzer.

---

## 13. Aplicación de PC

Pide una letra, valida que sea un solo carácter alfabético, la pasa a mayúscula y
la manda como un byte. Parsea los mensajes, muestra el patrón, los intentos que
quedan, cómo fue la última letra y el resultado final. No se cae con entradas
raras.

No guarda la palabra secreta, no elige la palabra, no decide quién gana y no
lleva el tiempo. Todo eso está en la FPGA.

---

## 14. Pines

| Función | Puerto | Dónde | Pin |
|---|---|---|---|
| Reloj | `clk_i` | | E3 |
| LCD `DB[3:0]` | `lcd_db_o[3:0]` | JA1–JA4 | B13, F14, D17, E17 |
| LCD `DB[7:4]` | `lcd_db_o[7:4]` | JA7–JA10 | G13, C17, D18, E18 |
| LCD `RS` | `lcd_rs_o` | JB1 | G14 |
| LCD `R/W` | `lcd_rw_o` | JB2 | P15 |
| LCD `E` | `lcd_e_o` | JB3 | V11 |
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

El PmodCLP ocupa el conector JA completo más la fila de arriba de JB, porque J1
lleva los ocho bits de datos y J2 las tres señales de control. Hay que
comprobarlo físicamente antes de la primera prueba. La revisión B funciona a
3.3 V, que es lo que dan los Pmod.

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
JB7–JB10 lo resuelve sin depender de nada de esto.

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
