package dev.offline.cache;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

/** A minimal JUnit 6.1.2 unit test, without project data or credentials. */
class OfflineCacheSeedTest {
    @Test
    void additionWorks() {
        assertEquals(5, OfflineCacheSeed.sum(2, 3));
    }
}
