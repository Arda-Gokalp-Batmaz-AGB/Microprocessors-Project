.section .vectors, "ax"
	B _start // reset vector
	B SERVICE_UND // undefined instruction vector
	B SERVICE_SVC // software interrrupt vector
	B SERVICE_ABT_INST // aborted prefetch vector
	B SERVICE_ABT_DATA // aborted data vector
	.word 0 // unused vector
	B SERVICE_IRQ // IRQ interrupt vector
	B SERVICE_FIQ // FIQ interrupt vector
	
// Constants
.equ UART_BASE, 0xFF201000     // UART base address
.equ BRAIN_MODE_MASK, 0b100
.equ MACHINE_MODE_MASK, 0b1000

.equ PANEL_DECISION_MASK, 0b10
.equ WRITING_MODE_MASK, 0b1

.equ MACHINE_BASE_ADDRESS, 0xFFFFea10 // MAX ADD  0xFFFFF300
.equ MACHINE_MAX_ADDRESS, 0xFFFFF300 // MAX ADD  
.equ MACHINE_POINTER_ADDRESS, 0xFFFFea00

.equ BRAIN_BASE_ADDRESS, 0xFFFF0110
.equ BRAIN_MAX_ADDRESS,  0xFFFFe9f0
.equ BRAIN_POINTER_ADDRESS, 0xFFFF0100

.equ MEMORY_RESET_MASK, 0xaaaaaaaa
//.equ MACHINE_CURRENT_ADDRESS, 0xFFFFea10
.org    0x1000    // Start at memory location 1000

.text  // Code Section
.global _start
_start:
	BL Init_Machine_And_Brain
	//R2 WILL BE MACHINE_CURRENT_ADDRESS POINTER
	//wWrite Panel
	LDR R12, =PANEL_DECISION_MASK
	LDR  R6, =DECISION_PANEL_STRING
	PUSH {R0-R11, LR}
	BL LoadText
	POP {R0-R11, LR}
	B InitInterrupts

Init_Machine_And_Brain:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, =MACHINE_BASE_ADDRESS
	STR R9,[R2]
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, =BRAIN_BASE_ADDRESS
	STR R9,[R2]
	BX LR
InitInterrupts:

	MOV R1, #0b11010010 // interrupts masked, MODE = IRQ
	MSR CPSR_c, R1 // change to IRQ mode
	LDR SP, =0xFFFFFFFF - 3 // set IRQ stack to A9 onchip memory

	/* Change to SVC (supervisor) mode with interrupts disabled */
	MOV R1, #0b11010011 // interrupts masked, MODE = SVC
	MSR CPSR, R1 // change to supervisor mode
	LDR SP, =0x3FFFFFFF - 3 // set SVC stack to top of DDR3 memory
	BL CONFIG_GIC // configure the ARM GIC

	// write to the pushbutton KEY interrupt mask register
	LDR R0, =UART_BASE // pushbutton KEY base address
	MOV R1, #0xF // set interrupt mask bits
	STR R1, [R0, #0x4] // interrupt mask register (base + 8)

	MOV R0, #0b01010011 // IRQ unmasked, MODE = SVC
	MSR CPSR_c, R0
IDLE:
	B IDLE // main program simply idles

/* Define the exception service routines */
/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
	B SERVICE_UND
/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
	B SERVICE_SVC
/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
	B SERVICE_ABT_DATA
/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
	B SERVICE_ABT_INST

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
	PUSH {R0-R11, LR}
	/* Read the ICCIAR from the CPU Interface */
	LDR R4, =0xFFFEC100
	LDR R5, [R4, #0x0C] // read from ICCIAR
FPGA_IRQ1_HANDLER:
	CMP R5, #80
UNEXPECTED:
	BNE UNEXPECTED // if not recognized, stop here
	B KEY_ISR
EXIT_IRQ:
	/* Write to the End of Interrupt Register (ICCEOIR) */
	STR R5, [R4, #0x10] // write to ICCEOIR
	POP {R0-R11, LR}
	SUBS PC, LR, #4
	
SERVICE_FIQ:
	B SERVICE_FIQ	
	
CONFIG_GIC:
	PUSH {LR}
/* To configure the FPGA KEYS interrupt (ID 73):
* 1. set the target to cpu0 in the ICDIPTRn register
* 2. enable the interrupt in the ICDISERn register */

/* CONFIG_INTERRUPT (int_ID (R0), CPU_target (R1)); */
	MOV R0, #80 // KEY port (Interrupt ID = 73)
	MOV R1, #1 // this field is a bit-mask; bit 0 targets cpu0
	BL CONFIG_INTERRUPT
	
	/* configure the GIC CPU Interface */
	LDR R0, =0xFFFEC100 // base address of CPU Interface
	
	/* Set Interrupt Priority Mask Register (ICCPMR) */
	LDR R1, =0xFFFF // enable interrupts of all priorities levels
	STR R1, [R0, #0x04]
	
	/* Set the enable bit in the CPU Interface Control Register (ICCICR).
	* This allows interrupts to be forwarded to the CPU(s) */
	MOV R1, #1
	STR R1, [R0]
	
	/* Set the enable bit in the Distributor Control Register (ICDDCR).
	* This enables forwarding of interrupts to the CPU Interface(s) */
	LDR R0, =0xFFFED000
	STR R1, [R0]
	POP {PC}

/*
* Configure registers in the GIC for an individual Interrupt ID
* We configure only the Interrupt Set Enable Registers (ICDISERn) and
* Interrupt Processor Target Registers (ICDIPTRn). The default (reset)
* values are used for other registers in the GIC
* Arguments: R0 = Interrupt ID, N
* R1 = CPU target
*/
CONFIG_INTERRUPT:
	PUSH {R4-R5, LR}
/* Configure Interrupt Set-Enable Registers (ICDISERn).
* reg_offset = (integer_div(N / 32) * 4
* value = 1 << (N mod 32) */
	LSR R4, R0, #3 // calculate reg_offset
	BIC R4, R4, #3 // R4 = reg_offset
	LDR R2, =0xFFFED100
	ADD R4, R2, R4 // R4 = address of ICDISER
	AND R2, R0, #0x1F // N mod 32
	MOV R5, #1 // enable
	LSL R2, R5, R2 // R2 = value
	
/* Using the register address in R4 and the value in R2 set the
* correct bit in the GIC register */
	LDR R3, [R4] // read current register value
	ORR R3, R3, R2 // set the enable bit
	STR R3, [R4] // store the new register value
	
/* Configure Interrupt Processor Targets Register (ICDIPTRn)
* reg_offset = integer_div(N / 4) * 4
* index = N mod 4 */
	BIC R4, R0, #3 // R4 = reg_offset
	LDR R2, =0xFFFED800
	ADD R4, R2, R4 // R4 = word address of ICDIPTR
	AND R2, R0, #0x3 // N mod 4
	ADD R4, R2, R4 // R4 = byte address in ICDIPTR
	
/* Using register address in R4 and the value in R2 write to
* (only) the appropriate byte */
	STRB R1, [R4]
	POP {R4-R5, PC}	
	
	
	








	
Init_Input_Loop:
	LDR  r1, =UART_BASE
	MOV R10, #0
	ADD R10,R1,#4
	MOV R7, #0b1
	STR R7,[R10]
	B InputLoop
InputLoop:
	LDRH R10, [R1]
	TST  R10, #0x8000
	BEQ END_INPUT_LOOP 
	AND R10,R10,#0xFF
	STR  R10, [r1] 
	CMP R10,#0x21
	BEQ Put_Info_To_Brain
	B Is_Waiting_Decision
	
	B InputLoop

Is_Waiting_Decision:
	CMP R12,#0b1
	BNE Check_Input_MASK
	B Store_Info_Input_To_Machine
	
End_Info_Input:
	//STORE ENTERED VALUES TO BRAIN
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, =MACHINE_BASE_ADDRESS
	STR R9,[R2]
	
	LDR R12, =PANEL_DECISION_MASK
	LDR  R6, =INFO_INPUT_SUCESS
	BL LoadText
	LDR  R6, =DECISION_PANEL_STRING
	BL LoadText
	
	B END_INPUT_LOOP

Check_Input_MASK:
	CMP R12,#0b10 
	BEQ Panel_Decision
	CMP R12,#0b100 
	BEQ Brain_Decision
	CMP R12,#0b1000 
	BEQ Injection_Decision
Panel_Decision:
	MOV R11, #0x0a
	STR R11, [R1]
	
	CMP R10,#0x31 // 1 ENTERED
	BEQ Open_Brain_Panel
	CMP R10,#0x32
	BEQ Open_Machine_Panel
	
	B Invalid_Request

Invalid_Request:
	LDR  R6, =INVALID_REQUEST_STRING
	BL LoadText
	B InputLoop
Open_Machine_Panel:
	//BEQ Open_Injection_Panel
	LDR  R6, =MACHINE_DECISION_STRING
	BL LoadText
	LDR R12, =MACHINE_MODE_MASK
	B InputLoop
Open_Brain_Panel:
	LDR  R6, =BRAIN_DECISION_STRING
	BL LoadText
	LDR R12, =BRAIN_MODE_MASK
	B InputLoop
Injection_Decision:
	LDR  R6, =INFO_PROMPT_STRING
	BL LoadText
	LDR R12, =WRITING_MODE_MASK
	B InputLoop
Brain_Decision:
	MOV R11, #0x0a
	STR R11, [R1]
	
	CMP R10,#0x31 // 1 ENTERED
	BEQ Show_Brain_Info
	
	B Invalid_Request
Show_Brain_Info:
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =BRAIN_BASE_ADDRESS
	MOV R6,R2
	BL LoadText
	B Show_Panel
_stop:
	B _stop

KEY_ISR:
	B Init_Input_Loop
Show_Panel:
	LDR R12, =PANEL_DECISION_MASK
	LDR  R6, =DECISION_PANEL_STRING
	BL LoadText
	B END_INPUT_LOOP
	
END_INPUT_LOOP:
	B EXIT_IRQ
	
	
Store_Info_Input_To_Machine:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	STRB R10, [R9]
	ADD R9,R9,#1
	STR R9,[R2]
	B InputLoop

Reset_Info_Input_Machine:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =MACHINE_BASE_ADDRESS
	B Reset_Info_Helper_Loop
Reset_Info_Helper_Loop:
	LDR R10, =MEMORY_RESET_MASK
	STR R10, [R2],#4
	CMP R2,R9
	BGE End_Info_Input
	B Reset_Info_Helper_Loop
	// ADD THEM TO BRAIN before reset
Put_Info_To_Brain:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =MACHINE_BASE_ADDRESS
	LDR R7, =BRAIN_POINTER_ADDRESS
	LDR R0,[R7]
	//LDR R0, =BRAIN_BASE_ADDRESS
	B Put_Info_To_Brain_Helper_Loop
Put_Info_To_Brain_Helper_Loop:
	LDRB R10, [R2]
	STRB R10,[R0]
	
	ADD R2,R2,#1
	ADD R0,R0,#1
	STR R0,[R7]
	CMP R9,R2
	BGE Put_Info_To_Brain_Helper_Loop
	SUB R0,R0,#1
	MOV R10, #0x0A
	STRB R10,[R0]
	ADD R0,R0,#1
	STRB R10,[R0]
	B Reset_Info_Input_Machine
	
	
	
LoadText:
	//Init Timer
	LDR R11, =0xFFFEC600 // PRIVATE TIMER
	LDR R10,=10000000
	STR R10,[R11]
	MOV R10, #0b011 
	STR R10, [R11, #0x8] 

	LDR  r1, =UART_BASE
	MOV R8,R7
	MOV R7,R6
	B WriteText
WriteText:
	LDRB r0, [R7]    // load a single byte from the string
	CMP  r0, #0
	BEQ  END_Write_Text  // stop when the null character is found
	CMP  r0, #0xaa
	BEQ  END_Write_Text
	B WAIT
	
Write_Text_Helper:
	STR  r0, [r1]    // copy the charact1er to the UART DATA field
	ADD  R7, R7, #1  // move to next character in memory
	B WriteText
END_Write_Text:
	MOV R7,R8
	MOV R8,#0
	MOV R10, #0b000
	STR R10, [R11, #0x8] 
	BX LR

WAIT: 
	LDR R10, [R11, #0xC] // read timer status
	CMP R10, #0
	BEQ WAIT
	STR R10, [R11, #0xC] 
	B Write_Text_Helper

	
.data  // Data Section
// Define a null-terminated string
INFO_PROMPT_STRING: // ADD CATEGORY // INFO cOUNT //DISPLAY
.asciz    "Enter Information You Want to Inject \n > "
MACHINE_DECISION_STRING: 
.asciz "\n Enter 1 to Open Injection , Enter 2 to see Machine's Situation \n >"
BRAIN_DECISION_STRING: // ADD CATEGORY // INFO cOUNT //DISPLAY
.asciz    "Enter 1 to see Brain Data, Enter 2 to see Brain's Situation, Enter 3 to see Reset Brain \n > "
INFO_INPUT_SUCESS:
.asciz    "\n Information injection to the Brain is Successfull! \n"
INVALID_REQUEST_STRING:
.asciz    "\n Please enter a valid decision input \n"
DECISION_PANEL_STRING: // ADD CATEGORY // INFO cOUNT
.asciz "\n Enter 1 to open Brain Panel , Enter 2 to open Machine Panel \n >"
INFO_STRING:
.asciz "Brain panel remove info, see infos, frequently used infos, remove some info in order to add new ones, reset buttons on brain and enter panel \033[2J"
.asciz    "Enter 1 To Inject Information to Brain \n Enter 2 to see Injected Information Enter 3 to see injected info in specific category, category count \n Enter 4 to show total info count \n Enter 5 to return main menu"
.end