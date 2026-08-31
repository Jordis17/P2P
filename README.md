# Ahorcado — juego electrónico FPGA / PC por enlace serial

Juego del Ahorcado sobre una **Digilent Nexys 4**, con una aplicación Python en la
PC que funciona como terminal remota a través de un enlace serial UART.

Curso: **EL3313 — Taller de Diseño Digital**

Toda la lógica del juego vive en la FPGA: el banco de palabras, la selección
pseudoaleatoria, la validación de letras, el temporizador, el conteo de errores y
la decisión del resultado. La PC solo envía la letra que el jugador escribe y
muestra lo que la FPGA responde.

| Modo | Palabras | Tiempo |
|---|---|---:|
| Fácil | cualquiera del banco | 60 s |
| Difícil | de 6 letras o más | 45 s |

---

## Estructura del repositorio

```
Ahorcado_juego_electrónico_FPGA_y_PC_por_enlace_serial/
└── FPGA/
    ├── DESIGN/                módulos .sv sintetizables y restricciones
    ├── SIMULATION/            testbenches .sv
    └── DOCUMENTATION/
        ├── *.md
        └── FIGURAS/

PYTHON/
├── DESIGN/                    aplicación de terminal y utilidades .py
└── DOCUMENTATION/
    ├── *.md
    └── FIGURAS/
```

El proyecto de Vivado no se versiona: es un artefacto generado. Las fuentes son
`FPGA/DESIGN` y `FPGA/SIMULATION`.

---

## Equipo

| Integrante | Bloque | Módulos |
|---|---|---|
| Mariana Fallas Fallas | Núcleo del juego | `game_controller`, `lfsr`, `round_timer`, `word_rom` |
| Abner López Méndez | Subsistema LCD | `lcd_controller`, `lcd_peripheral`, `lcd_screen_ctrl` |
| Justin Garita Serrano | UART y aplicación de PC | `uart_peripheral`, `uart_msg_tx`, `uart_test_block`, terminal |
| Jordi Segura Chinchilla | Periféricos locales e integración | `clk_tick_gen`, `button_input`, `display_controller`, `buzzer_controller`, `led_controller`, `top`, restricciones |

Cada quien es dueño de sus módulos y de sus testbenches.

---

## Dependencias

| Herramienta | Versión | Para qué |
|---|---|---|
| Xilinx Vivado | 2019.2 o superior | síntesis, implementación, simulación |
| Digilent Nexys 4 | rev. B | implementación física |
| PmodCLP | rev. B, 3.3 V | LCD 16×2, controlador Samsung KS0066 |
| Python | 3.8 o superior | terminal y generador del banco |
| pyserial | `pip install pyserial` | comunicación UART desde la PC |

Se necesita además un altavoz amplificado o audífonos en el jack de 3.5 mm: la
Nexys 4 no lleva buzzer y la retroalimentación sonora sale por el amplificador
PWM integrado.

---

## Conexión del hardware

El PmodCLP usa interfaz paralela de 8 bits y ocupa un conector Pmod completo más
media fila de otro:

| PmodCLP | Señales | Conector |
|---|---|---|
| J1, 12 pines | `DB0`–`DB7` | JA completo |
| J2, 6 pines | `RS`, `R/W`, `E` | JB1–JB3 |

| Botón | Función |
|---|---|
| Central (`BTNC`) | reinicio general |
| Izquierdo (`BTNL`) | alterna Fácil / Difícil |
| Derecho (`BTNR`) | confirma el modo e inicia la partida |

El mapeo completo está en `FPGA/DESIGN/nexys4_ahorcado.xdc`.

---

## Compilación e implementación

Desde la consola Tcl de Vivado, con el proyecto creado sobre las fuentes de
`FPGA/DESIGN`:

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

Después, programar la tarjeta desde el Hardware Manager.

Antes de dar por terminada la implementación hay que revisar el timing summary,
el slack, la frecuencia máxima y que no se hayan inferido latches.

---

## Simulación

Los testbenches de `FPGA/SIMULATION` son autoverificables: comprueban los
resultados y terminan con un resumen de PASS/FAIL, sin necesidad de inspeccionar
formas de onda.

La simulación post-implementación temporizada se corre sobre una variante con las
constantes de tiempo reducidas, para que el arranque del LCD y las tramas UART
sean simulables en un tiempo razonable.

---

## Regenerar el banco de palabras

`FPGA/DESIGN/word_rom.sv` es un archivo generado. La lista de palabras vive
dentro de `PYTHON/DESIGN/gen_word_rom.py`.

```bash
cd PYTHON/DESIGN
python gen_word_rom.py           # valida y regenera word_rom.sv
python gen_word_rom.py --check   # solo valida
```

El script comprueba que haya 64 palabras distintas, que los índices 0–31 sean de
6 letras o más, que los 32–63 sean de 4 o 5, y que no haya caracteres fuera de
A-Z. De ese orden depende la selección de palabra: en modo difícil el índice sale
de los cinco bits bajos del LFSR, así que no puede caer fuera del rango largo.

---

## Ejecutar la aplicación de PC

```bash
cd PYTHON/DESIGN
pip install pyserial
python ahorcado_terminal.py --port COM4          # Windows
python ahorcado_terminal.py --port /dev/ttyUSB0  # Linux
```

Enlace a 115200 baudios. Para saber el puerto: en Windows, Administrador de
dispositivos, *Puertos (COM y LPT)*; en Linux, `ls /dev/ttyUSB*`.

---

## Protocolo

Mensajes ASCII terminados en salto de línea, con campos de ancho fijo.

**PC a FPGA:** un byte, de la `A` a la `Z`.

**FPGA a PC:**

| Mensaje | Formato | Cuándo |
|---|---|---|
| `START:<M>:<LL>` | modo y longitud | al iniciar la partida |
| `PATT:<p>` | patrón, `_` en lo oculto | al iniciar y tras cada letra |
| `LET:<X>:<R>` | letra y resultado: `OK `, `NO `, `RPT` | al evaluar una letra |
| `ERR:<n>` | intentos fallidos restantes | al iniciar y tras cada letra |
| `END:<E>:<W>` | causa y palabra secreta | al terminar |

```
START:F:07
PATT:_______
ERR:6
LET:A:OK
PATT:A______
ERR:6
LET:Z:NO
PATT:A______
ERR:5
END:LTO:AVIONES
```

El tiempo restante no se transmite: se muestra en los displays de 7 segmentos.
