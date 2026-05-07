tags {"repl aof external:skip"} {
    test {Active-active AOF RDB preamble restart preserves MVCC clocks} {
        start_server {overrides {appendonly yes aof-use-rdb-preamble yes save "" active-replica yes multi-master yes replica-read-only no}} {
            set node [srv 0 client]

            waitForBgrewriteaof $node
            assert_error {*requires active-replica-debug-commands yes*} {$node config set mvcc-rdb-clock-max-entries 1}
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

            $node set mm:aof-del doomed
            set deleted_payload [$node dump mm:aof-del]
            after 1
            $node del mm:aof-del
            assert_equal {} [$node get mm:aof-del]

            $node mset mm:aof-mset:a old-a mm:aof-mset:b old-b
            set stale_mset_a_payload [$node dump mm:aof-mset:a]
            set stale_mset_b_payload [$node dump mm:aof-mset:b]
            after 1
            $node mset mm:aof-mset:a new-a mm:aof-mset:b new-b
            assert_equal new-a [$node get mm:aof-mset:a]
            assert_equal new-b [$node get mm:aof-mset:b]

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
            assert_equal {} [$node get mm:aof-del]
            $node mvccrestore mm:aof-del 0 $deleted_payload 1 replace
            assert_equal {} [$node get mm:aof-del]
            assert_equal new-a [$node get mm:aof-mset:a]
            assert_equal new-b [$node get mm:aof-mset:b]
            $node mvccrestore mm:aof-mset:a 0 $stale_mset_a_payload 1 replace
            $node mvccrestore mm:aof-mset:b 0 $stale_mset_b_payload 1 replace
            assert_equal new-a [$node get mm:aof-mset:a]
            assert_equal new-b [$node get mm:aof-mset:b]
        }
    }
}
