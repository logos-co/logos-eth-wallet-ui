.pragma library

// A backend error as a person reads it: a leading machine code such as "WrongSecret: " is
// dropped and the sentence is kept as the backend worded it (it may open on a field name, such
// as maxPriorityFeePerGas, whose case is part of it). Empty in, empty out.
function human(e) {
    return String(e || "").trim().replace(/^[A-Z][A-Za-z]+:\s*/, "")
}
