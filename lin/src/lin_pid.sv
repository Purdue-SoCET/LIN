// lin_pid
// Implements: LIN-GEN-02, LIN-GEN-05, LIN-PROT-04
module lin_pid (
    input  logic [5:0] id_in,
    input  logic [7:0] pid_in,
    output logic [7:0] pid_out,
    output logic       pid_err
);
    logic p0, p1;
    assign p0 = id_in[0] ^ id_in[1] ^ id_in[2] ^ id_in[4];
    assign p1 = ~(id_in[1] ^ id_in[3] ^ id_in[4] ^ id_in[5]);
    assign pid_out = {p1, p0, id_in};
    assign pid_err = (pid_in != pid_out);
endmodule
