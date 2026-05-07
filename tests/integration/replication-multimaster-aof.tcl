tags {"repl aof external:skip"} {
    test {Active-active AOF RDB preamble restart preserves MVCC clocks} {
        start_server {overrides {appendonly yes aof-use-rdb-preamble yes save "" active-replica yes multi-master yes replica-read-only no}} {
            set node [srv 0 client]

            waitForBgrewriteaof $node
            $node config set active-replica-debug-commands yes

            $node set mm:aof-mvcc stale
            set stale_payload [$node dump mm:aof-mvcc]
            after 1
            $node set mm:aof-mvcc fresh
            assert_equal fresh [$node get mm:aof-mvcc]

            assert_match {*Background append only file rewriting started*} [$node bgrewriteaof]
            waitForBgrewriteaof $node

            $node set mm:aof-tail stale-tail
            set stale_tail_payload [$node dump mm:aof-tail]
            after 1
            $node set mm:aof-tail fresh-tail
            assert_equal fresh-tail [$node get mm:aof-tail]

            restart_server 0 true false
            set node [srv 0 client]
            wait_for_condition 100 100 {
                [s 0 loading] eq {0}
            } else {
                fail "Node restart after AOF rewrite did not finish loading"
            }

            $node config set active-replica-debug-commands yes
            assert_equal fresh [$node get mm:aof-mvcc]
            $node mvccrestore mm:aof-mvcc 0 $stale_payload 1 replace
            assert_equal fresh [$node get mm:aof-mvcc]
            assert_equal fresh-tail [$node get mm:aof-tail]
            $node mvccrestore mm:aof-tail 0 $stale_tail_payload 1 replace
            assert_equal fresh-tail [$node get mm:aof-tail]
        }
    }
}
