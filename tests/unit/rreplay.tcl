start_server {tags {"rreplay"}} {
    test {RREPLAY command is registered} {
        set cmdinfo [r command info rreplay]
        assert {[llength $cmdinfo] == 1}
        set info [lindex $cmdinfo 0]
        assert_equal rreplay [lindex $info 0]
        assert_equal -5 [lindex $info 1]

        set ackinfo [r command info rreplayack]
        assert {[llength $ackinfo] == 1}
        set ack [lindex $ackinfo 0]
        assert_equal rreplayack [lindex $ack 0]
        assert_equal 4 [lindex $ack 1]
    }

    test {RREPLAY is rejected for normal clients} {
        assert_error "*replication*peer-forward*" {
            r rreplay 0123456789abcdef0123456789abcdef01234567 0 1 set k v
        }
    }

    test {RREPLAYACK is gated as an internal debug command} {
        assert_error "*RREPLAYACK is internal*" {
            r rreplayack 127.0.0.1 1 1
        }
    }
}
