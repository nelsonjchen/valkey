---- MODULE MultiMaster_TTrace_1778107137 ----
EXTENDS Sequences, TLCExt, Toolbox, MultiMaster, Naturals, TLC

_expression ==
    LET MultiMaster_TEExpression == INSTANCE MultiMaster_TEExpression
    IN MultiMaster_TEExpression!expression
----

_trace ==
    LET MultiMaster_TETrace == INSTANCE MultiMaster_TETrace
    IN MultiMaster_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        nextId = ([A |-> 2, B |-> 1])
        /\
        store = ([A |-> [x |-> [origin |-> "A", id |-> 1, value |-> "v1", ts |-> 1]], B |-> [x |-> [origin |-> "none", id |-> 0, value |-> "none", ts |-> 0]]])
        /\
        net = ({})
        /\
        seen = ([A |-> {}, B |-> {}])
    )
----

_init ==
    /\ seen = _TETrace[1].seen
    /\ store = _TETrace[1].store
    /\ net = _TETrace[1].net
    /\ nextId = _TETrace[1].nextId
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ seen  = _TETrace[i].seen
        /\ seen' = _TETrace[j].seen
        /\ store  = _TETrace[i].store
        /\ store' = _TETrace[j].store
        /\ net  = _TETrace[i].net
        /\ net' = _TETrace[j].net
        /\ nextId  = _TETrace[i].nextId
        /\ nextId' = _TETrace[j].nextId

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MultiMaster_TTrace_1778107137.json", _TETrace)

=============================================================================

 Note that you can extract this module `MultiMaster_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `MultiMaster_TEExpression.tla` file takes precedence 
  over the module `MultiMaster_TEExpression` below).

---- MODULE MultiMaster_TEExpression ----
EXTENDS Sequences, TLCExt, Toolbox, MultiMaster, Naturals, TLC

expression == 
    [
        \* To hide variables of the `MultiMaster` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        seen |-> seen
        ,store |-> store
        ,net |-> net
        ,nextId |-> nextId
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_seenUnchanged |-> seen = seen'
        
        \* Format the `seen` variable as Json value.
        \* ,_seenJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(seen)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_seenModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].seen # _TETrace[s-1].seen
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE MultiMaster_TETrace ----
\*EXTENDS IOUtils, MultiMaster, TLC
\*
\*trace == IODeserialize("MultiMaster_TTrace_1778107137.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MultiMaster_TETrace ----
EXTENDS MultiMaster, TLC

trace == 
    <<
    ([nextId |-> [A |-> 1, B |-> 1],store |-> [A |-> [x |-> [origin |-> "none", id |-> 0, value |-> "none", ts |-> 0]], B |-> [x |-> [origin |-> "none", id |-> 0, value |-> "none", ts |-> 0]]],net |-> {},seen |-> [A |-> {}, B |-> {}]]),
    ([nextId |-> [A |-> 2, B |-> 1],store |-> [A |-> [x |-> [origin |-> "A", id |-> 1, value |-> "v1", ts |-> 1]], B |-> [x |-> [origin |-> "none", id |-> 0, value |-> "none", ts |-> 0]]],net |-> {},seen |-> [A |-> {}, B |-> {}]])
    >>
----


=============================================================================

---- CONFIG MultiMaster_TTrace_1778107137 ----
CONSTANTS
    Nodes = { "A" , "B" }
    Keys = { "x" }
    Values = { "v1" , "v2" }
    None = "none"
    MaxTs = 2
    AllowUnsupported = TRUE

INVARIANT
    _inv

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Wed May 06 15:38:57 PDT 2026