## =====================================================================
## Proyecto 2 - Ahorcado FPGA/PC
## Digilent Nexys 4 (rev B) - XDC del proyecto
##
## Derivado de:
##   - Constrains.txt (plantilla general de Digilent para Nexys4 rev B)
##   - Nexys 4 Reference Manual (polaridades)
##   - pmodclp_rm.pdf (pinout del PmodCLP: J1 = DB0..DB7, J2 = RS, R/W, E)
##   - Notas de diseno del proyecto, seccion 14 (mapeo de pines)
##
## POLARIDADES (segun el Nexys 4 Reference Manual):
##   pulsadores BTNC/U/D/L/R : activos en ALTO
##   CPU_RESET               : activo en BAJO  (NO lo usamos)
##   LEDs                    : encienden en ALTO
##   segmentos CA..CG        : activos en BAJO
##   anodos AN0..AN7         : activos en BAJO
##   Se aplican en el top mediante BTN_ACTIVE_LEVEL, LED_ACTIVE_LEVEL,
##   SEG_ACTIVE_LEVEL y AN_ACTIVE_LEVEL. Este archivo solo fija PINES.
## =====================================================================

## ---------------------------------------------------------------------
## Reloj de sistema - 100 MHz
## Bank 35, Sch name = CLK100MHZ
## ---------------------------------------------------------------------
set_property PACKAGE_PIN E3 [get_ports clk_i]
    set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
    create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports clk_i]

## ---------------------------------------------------------------------
## Pulsadores
##   BTN_RST va en el boton central.
##   ATENCION: btnCpuReset (C12) es un boton DISTINTO y de polaridad
##   opuesta. No usarlo ni confundirlo con btnC.
## ---------------------------------------------------------------------
set_property PACKAGE_PIN E16 [get_ports btn_rst_i]
    set_property IOSTANDARD LVCMOS33 [get_ports btn_rst_i]
set_property PACKAGE_PIN T16 [get_ports btn_sel_i]
    set_property IOSTANDARD LVCMOS33 [get_ports btn_sel_i]
set_property PACKAGE_PIN R10 [get_ports btn_ok_i]
    set_property IOSTANDARD LVCMOS33 [get_ports btn_ok_i]

## ---------------------------------------------------------------------
## UART - USB-RS232 (115200 baudios)
##   RsRx = UART_TXD_IN : ENTRADA a la FPGA
##   RsTx = UART_RXD_OUT: SALIDA de la FPGA
## ---------------------------------------------------------------------
set_property PACKAGE_PIN C4 [get_ports uart_rx_i]
    set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
set_property PACKAGE_PIN D4 [get_ports uart_tx_o]
    set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]

## ---------------------------------------------------------------------
## PmodCLP - LCD 16x2, controlador Samsung KS0066 (compatible HD44780)
## Interfaz paralela de 8 bits. R/W atado a 0 en el RTL.
##
## Conexion fisica (verificar antes de la primera prueba):
##   PmodCLP J1 (12 pines) -> Pmod JA completo   : DB0..DB7
##   PmodCLP J2 (6 pines)  -> Pmod JB fila sup.  : RS, R/W, E
## El PmodCLP rev B requiere alimentacion de 3.3 V (la que dan los Pmod).
## ---------------------------------------------------------------------
## DB[3:0] -> JA1..JA4
set_property PACKAGE_PIN B13 [get_ports {lcd_db_o[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[0]}]
set_property PACKAGE_PIN F14 [get_ports {lcd_db_o[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[1]}]
set_property PACKAGE_PIN D17 [get_ports {lcd_db_o[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[2]}]
set_property PACKAGE_PIN E17 [get_ports {lcd_db_o[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[3]}]
## DB[7:4] -> JA7..JA10
set_property PACKAGE_PIN G13 [get_ports {lcd_db_o[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[4]}]
set_property PACKAGE_PIN C17 [get_ports {lcd_db_o[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[5]}]
set_property PACKAGE_PIN D18 [get_ports {lcd_db_o[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[6]}]
set_property PACKAGE_PIN E18 [get_ports {lcd_db_o[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {lcd_db_o[7]}]
## Control -> JB1..JB3
set_property PACKAGE_PIN G14 [get_ports lcd_rs_o]
    set_property IOSTANDARD LVCMOS33 [get_ports lcd_rs_o]
set_property PACKAGE_PIN P15 [get_ports lcd_rw_o]
    set_property IOSTANDARD LVCMOS33 [get_ports lcd_rw_o]
set_property PACKAGE_PIN V11 [get_ports lcd_e_o]
    set_property IOSTANDARD LVCMOS33 [get_ports lcd_e_o]

## ---------------------------------------------------------------------
## Salida de audio (retroalimentacion sonora)
##   La Nexys 4 NO tiene buzzer. Se usa la salida de audio mono que
##   pasa por un filtro paso bajo y sale por el jack de 3.5 mm: la
##   demostracion requiere altavoz amplificado o audifonos.
##
##   PENDIENTE antes de cablear esto:
##     - AUD_SD no aparece en el Reference Manual pese a estar en la
##       plantilla de Digilent. Falta confirmar que hace y con que nivel.
##     - El manual de la Nexys 4 DDR describe la entrada del filtro como
##       colector abierto (bajo para '0', alta impedancia para '1'). Si
##       aqui pasa igual, aud_pwm_o no puede ser una salida normal.
##   Revisar el esquematico de la tarjeta antes de dar esto por bueno.
## ---------------------------------------------------------------------
set_property PACKAGE_PIN A11 [get_ports aud_pwm_o]
    set_property IOSTANDARD LVCMOS33 [get_ports aud_pwm_o]
set_property PACKAGE_PIN D12 [get_ports aud_sd_o]
    set_property IOSTANDARD LVCMOS33 [get_ports aud_sd_o]

## ---------------------------------------------------------------------
## Display de 7 segmentos
##   Se usan AN3..AN0. AN7..AN4 deben quedar explicitamente apagados.
##   seg_o[6:0] = CA, CB, CC, CD, CE, CF, CG
## ---------------------------------------------------------------------
set_property PACKAGE_PIN L3 [get_ports {seg_o[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[0]}]
set_property PACKAGE_PIN N1 [get_ports {seg_o[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[1]}]
set_property PACKAGE_PIN L5 [get_ports {seg_o[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[2]}]
set_property PACKAGE_PIN L4 [get_ports {seg_o[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[3]}]
set_property PACKAGE_PIN K3 [get_ports {seg_o[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[4]}]
set_property PACKAGE_PIN M2 [get_ports {seg_o[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[5]}]
set_property PACKAGE_PIN L6 [get_ports {seg_o[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {seg_o[6]}]

set_property PACKAGE_PIN N6 [get_ports {an_o[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[0]}]
set_property PACKAGE_PIN M6 [get_ports {an_o[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[1]}]
set_property PACKAGE_PIN M3 [get_ports {an_o[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[2]}]
set_property PACKAGE_PIN N5 [get_ports {an_o[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[3]}]
set_property PACKAGE_PIN N2 [get_ports {an_o[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[4]}]
set_property PACKAGE_PIN N4 [get_ports {an_o[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[5]}]
set_property PACKAGE_PIN L1 [get_ports {an_o[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[6]}]
set_property PACKAGE_PIN M1 [get_ports {an_o[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {an_o[7]}]

## ---------------------------------------------------------------------
## LEDs de estado
##   led_o[0] = MODE_SELECT
##   led_o[1] = PLAYING
##   led_o[2] = RESULT          (los tres son mutuamente excluyentes)
##   led_o[15] = modo: apagado = FACIL, encendido = DIFICIL
##
## Se restringen los dieciseis aunque el juego solo use cuatro. El puerto
## del bloque superior es de 16 bits y Vivado no genera el bitstream si
## queda algun pin de entrada o salida sin asignar. Ademas, en modo de
## prueba del UART los LEDs muestran el ultimo byte recibido, que usa los
## ocho de abajo.
## ---------------------------------------------------------------------
set_property PACKAGE_PIN T8 [get_ports {led_o[0]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[0]}]
set_property PACKAGE_PIN V9 [get_ports {led_o[1]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[1]}]
set_property PACKAGE_PIN R8 [get_ports {led_o[2]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[2]}]
set_property PACKAGE_PIN T6 [get_ports {led_o[3]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[3]}]
set_property PACKAGE_PIN T5 [get_ports {led_o[4]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[4]}]
set_property PACKAGE_PIN T4 [get_ports {led_o[5]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[5]}]
set_property PACKAGE_PIN U7 [get_ports {led_o[6]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[6]}]
set_property PACKAGE_PIN U6 [get_ports {led_o[7]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[7]}]
set_property PACKAGE_PIN V4 [get_ports {led_o[8]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[8]}]
set_property PACKAGE_PIN U3 [get_ports {led_o[9]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[9]}]
set_property PACKAGE_PIN V1 [get_ports {led_o[10]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[10]}]
set_property PACKAGE_PIN R1 [get_ports {led_o[11]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[11]}]
set_property PACKAGE_PIN P5 [get_ports {led_o[12]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[12]}]
set_property PACKAGE_PIN U1 [get_ports {led_o[13]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[13]}]
set_property PACKAGE_PIN R2 [get_ports {led_o[14]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[14]}]
set_property PACKAGE_PIN P2 [get_ports {led_o[15]}]
    set_property IOSTANDARD LVCMOS33 [get_ports {led_o[15]}]

## ---------------------------------------------------------------------
## Pines Pmod libres reservados para buzzer alternativo (plan B)
##   JB7..JB10 = K16, R16, T9, U11
## ---------------------------------------------------------------------
