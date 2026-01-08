package example

default allow := false

allow if {
	input.user == "admin"
}

allow if {
	input.action == "read"
}

result := {"allow": allow}
