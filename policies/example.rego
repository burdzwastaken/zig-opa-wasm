package example

default allow := false

allow if {
	input.user == "admin"
}
