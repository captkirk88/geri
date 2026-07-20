package errors

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:testing"

Error :: struct {
	message:  string,
	payload:  any,
	location: runtime.Source_Code_Location,
	cause:    ^Error,
}

none :: proc() -> Error {
	return Error{}
}

new :: proc(
	message: string,
	payload: any = nil,
	cause: ^Error = nil,
	location := #caller_location,
) -> Error {
	return Error{message = message, payload = payload, location = location, cause = cause}
}

new_fmt :: proc(
	format: string,
	args: ..any,
	payload: any = nil,
	cause: ^Error = nil,
	location := #caller_location,
) -> Error {
	return Error {
		message = fmt.tprintf(format, args),
		payload = payload,
		location = location,
		cause = cause,
	}
}

// Creates an Error with only a payload (no message), capturing the caller location.
from_payload :: proc(payload: any, cause: ^Error = nil, location := #caller_location) -> Error {
	return new("", payload, cause, location)
}

// Checks if the error's payload is of type T.
is :: proc(err: Error, $T: typeid) -> bool {
	return err.payload.id == T
}

// Safely retrieves the payload if it is of type T.
get_payload :: proc(err: Error, $T: typeid) -> (T, bool) {
	if err.payload.id == T {
		return (^T)(err.payload.data)^, true
	}
	return {}, false
}

// Formats the error and its cause chain into a string.
// The returned string must be freed by the caller.
format :: proc(err: Error, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)

	temp_err := err
	curr := &temp_err
	for curr != nil {
		if curr != &temp_err {
			strings.write_string(&b, "\ncaused by: ")
		}
		fmt.sbprintf(&b, "%s (%s:%d)", curr.message, curr.location.file_path, curr.location.line)
		if curr.payload != nil {
			fmt.sbprintf(&b, " [payload: %v]", curr.payload)
		}
		curr = curr.cause
	}
	return strings.to_string(b)
}

// Helper to check conditions and return an optional Error.
expect :: proc(
	cond: bool,
	message: string,
	payload: any = nil,
	location := #caller_location,
) -> (
	Error,
	bool,
) {
	if !cond {
		return new(message, payload, nil, location), false
	}
	return {}, true
}

@(private)
MyPayload :: struct {
	code:    int,
	details: string,
}

@(test)
test_errors_extensibility :: proc(t: ^testing.T) {
	err := new("Database connection failed", MyPayload{code = 500, details = "Timeout"})

	testing.expect(t, is(err, MyPayload))

	payload, ok := get_payload(err, MyPayload)
	testing.expect(t, ok)
	testing.expect_value(t, payload.code, 500)
	testing.expect_value(t, payload.details, "Timeout")

	// Check false types
	testing.expect(t, !is(err, int))
	_, ok_int := get_payload(err, int)
	testing.expect(t, !ok_int)
}

@(test)
test_errors_chaining :: proc(t: ^testing.T) {
	root := new("Root cause error")
	err := new("Wrapper error", nil, &root)

	testing.expect(t, err.cause != nil)
	testing.expect_value(t, err.cause.message, "Root cause error")

	str := format(err)
	defer delete(str)
	testing.expect(t, strings.contains(str, "Wrapper error"))
	testing.expect(t, strings.contains(str, "caused by: Root cause error"))
}
