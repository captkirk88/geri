package errors

import "core:fmt"
import "core:testing"


Result :: union($T: typeid, $E: typeid) {
	Ok(T),
	Err(E),
}

Ok :: struct($T: typeid) {
	value: T,
}

Err :: struct($E: typeid) {
	error: E,
}

is_ok :: proc(rs: Result($T, $E)) -> bool {
	#partial switch type in rs {
	case Ok(T):
		return true
	}
	return false
}

is_err :: proc(rs: Result($T, $E)) -> bool {
	return !is_ok(rs)
}

wrap :: proc(rs: Result($T, $E)) -> T {
	result: T
	switch v in rs {
	case Err(E):
		err := rs.(Err(E))
		fmt.panicf("Attempt to unrap Result.Err with message: `%s`", err.error)
	case Ok(T):
		ok := rs.(Ok(T))
		return ok.value
	}
	return result
}

unwrap_or :: proc(rs: Result($T, $E), value: T) -> T {
	result: T
	switch v in rs {
	case Err(E):
		return value
	case Ok(T):
		ok := rs.(Ok(T))
		return ok.value
	}
	return result
}

unwrap_orelse :: proc(rs: Result($T, $E), func: proc(rs: Result(T, E)) -> T) -> T {
	result: T
	switch v in rs {
	case Err(E):
		return func(rs)
	case Ok(T):
		ok := rs.(Ok(T))
		return ok.value
	}
	return result
}


unwrap_err :: proc(rs: Result($T, $E)) -> E {
	err: string
	switch v in rs {
	case Err(E):
		err := rs.(Err(E))
		return err.error
	case Ok(T):
		fmt.panicf("Attempt to unwrap Result.Ok")
	}
	return err
}

result_map :: proc(rs: Result($T, $E), procedure: proc(val: T) -> $U) -> Result(U, E) {
	switch v in rs {
	case Err(E):
		return v
	case Ok(T):
		return Ok(U){value = procedure(v.value)}
	}
	panic("unreachable")
}


map_err :: proc(rs: Result($T, $E), procedure: proc(err: E) -> $F) -> Result(T, F) {
	switch v in rs {
	case Err(E):
		return Err(F){error = procedure(v.error)}
	case Ok(T):
		return v
	}
	panic("unreachable")
}

@(test)
test_result_map :: proc(t: ^testing.T) {
	// Map Ok(int) to Ok(string)
	ok_val := Ok(int) {
		value = 42,
	}
	rs_ok: Result(int, string) = ok_val

	mapped_ok := result_map(rs_ok, proc(val: int) -> string {
		if val == 42 {return "hello"} else {return "world"}
	})

	testing.expect(t, is_ok(mapped_ok))
	testing.expect_value(t, mapped_ok.(Ok(string)).value, "hello")

	// Map Err(string) - should remain Err(string) when result_map is called
	err_val := Err(string) {
		error = "fail",
	}
	rs_err: Result(int, string) = err_val

	mapped_err := result_map(rs_err, proc(val: int) -> string {
		return "hello"
	})

	testing.expect(t, is_err(mapped_err))
	testing.expect_value(t, mapped_err.(Err(string)).error, "fail")
}

@(test)
test_result_map_err :: proc(t: ^testing.T) {
	// Map Err(int) to Err(bool)
	err_val := Err(int) {
		error = 100,
	}
	rs_err: Result(string, int) = err_val

	mapped_err := map_err(rs_err, proc(err: int) -> bool {
		return err == 100
	})

	testing.expect(t, is_err(mapped_err))
	testing.expect_value(t, mapped_err.(Err(bool)).error, true)

	// Map Ok(string) - should remain Ok(string) when map_err is called
	ok_val := Ok(string) {
		value = "hello",
	}
	rs_ok: Result(string, int) = ok_val

	mapped_ok := map_err(rs_ok, proc(err: int) -> bool {
		return err == 100
	})

	testing.expect(t, is_ok(mapped_ok))
	testing.expect_value(t, mapped_ok.(Ok(string)).value, "hello")
}
