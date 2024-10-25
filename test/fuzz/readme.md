## fuzz testing
supply random data to system in an attempt to break it
### usage
   - understand the invariants
   - write a fuzz test for invariant
### stateless fuzzing
   Stateless fuzzing generates and tests inputs independently, without considering any previous inputs, outputs, or system states
### stateful fuzzing
   Stateful fuzzing is an advanced fuzzing technique that takes into account the state of the system or application being tested. Unlike stateless fuzzing, which treats each input independently, stateful fuzzing considers the sequence of inputs and how they affect the system's state over time