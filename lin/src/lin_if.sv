// lin_if
// Implements: LIN-IF-01, LIN-IF-09
interface lin_if;
    logic tx, tx_en, rx, irq;
    modport peripheral (
        output tx, tx_en, irq,
        input  rx
    );
    modport soc (
        input  tx, tx_en, irq,
        output rx
    );
endinterface
