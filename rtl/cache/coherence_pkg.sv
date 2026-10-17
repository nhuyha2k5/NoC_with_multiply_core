package coherence_pkg;
  typedef enum logic [1:0] {
    MESI_INVALID   = 2'b00,
    MESI_SHARED    = 2'b01,
    MESI_EXCLUSIVE = 2'b10,
    MESI_MODIFIED  = 2'b11
  } mesi_state_e;

  typedef enum logic [1:0] {
    COH_GETS    = 2'b00,
    COH_GETM    = 2'b01,
    COH_UPGRADE = 2'b10
  } coherence_request_e;

  typedef enum logic {
    SNOOP_READ_SHARED = 1'b0,
    SNOOP_INVALIDATE  = 1'b1
  } snoop_command_e;
endpackage
