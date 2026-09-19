/* Short-lived Root HTTP check. Never installs routes or changes a process network.
 * Android's Network fwmark alone loses to our overlay rule; bind the actual
 * device AND its current IPv4 address so the phone's own TUN cannot answer. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int wait_fd(int fd, short events, long long deadline) {
    for (;;) {
        long long left = deadline - now_ms();
        if (left <= 0) return 0;
        struct pollfd p = { .fd = fd, .events = events };
        int n = poll(&p, 1, (int)left);
        if (n < 0 && errno == EINTR) continue;
        return n > 0 && (p.revents & (events | POLLHUP));
    }
}

static int invalid(const char *reason) { fprintf(stderr, "%s\n", reason); return 2; }

int main(int argc, char **argv) {
    if (argc != 5) return invalid("Expected Wi-Fi interface, source IPv4, target IPv4 and port");
    const char *iface = argv[1];
    if (strncmp(iface, "wlan", 4) || !iface[4] || strlen(iface) >= IFNAMSIZ ||
        strspn(iface + 4, "0123456789") != strlen(iface + 4)) return invalid("Invalid Wi-Fi interface");
    struct sockaddr_in source = { .sin_family = AF_INET }, target = { .sin_family = AF_INET };
    if (inet_pton(AF_INET, argv[2], &source.sin_addr) != 1 ||
        inet_pton(AF_INET, argv[3], &target.sin_addr) != 1) return invalid("Invalid IPv4 address");
    unsigned first = ntohl(target.sin_addr.s_addr) >> 24;
    if (first == 0 || first == 127 || first >= 224 ||
        (ntohl(target.sin_addr.s_addr) >> 16) == 0xa9fe) return invalid("Unsupported target address");
    if (!argv[4][0] || strspn(argv[4], "0123456789") != strlen(argv[4])) return invalid("Invalid port");
    errno = 0;
    unsigned long port = strtoul(argv[4], NULL, 10);
    if (errno || !port || port > 65535) return invalid("Invalid port");
    target.sin_port = htons((unsigned short)port);

    struct ifaddrs *addrs;
    if (getifaddrs(&addrs)) return invalid("Cannot inspect Wi-Fi addresses");
    int present = 0, self = 0;
    for (struct ifaddrs *a = addrs; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
        struct in_addr ip = ((struct sockaddr_in *)a->ifa_addr)->sin_addr;
        if (!strcmp(a->ifa_name, iface) && (a->ifa_flags & IFF_UP) && ip.s_addr == source.sin_addr.s_addr) present = 1;
        if (ip.s_addr == target.sin_addr.s_addr) self = 1;
    }
    freeifaddrs(addrs);
    if (!present) return invalid("Wi-Fi address changed or interface unavailable");
    if (self) return invalid("Target is this device, not the home gateway's network");

    int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) return invalid("Cannot create probe socket");
    if (setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, iface, strlen(iface) + 1) ||
        bind(fd, (struct sockaddr *)&source, sizeof(source))) {
        close(fd);
        return invalid("Cannot bind probe to Wi-Fi");
    }
    const long long deadline = now_ms() + 2500;
    int reachable = 0;
    if (connect(fd, (struct sockaddr *)&target, sizeof(target))) {
        if (errno != EINPROGRESS || !wait_fd(fd, POLLOUT, deadline)) goto done;
        int error = 0;
        socklen_t size = sizeof(error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) || error) goto done;
    }
    char request[192];
    int len = snprintf(request, sizeof(request), "HEAD / HTTP/1.1\r\nHost: %s:%lu\r\nConnection: close\r\n\r\n", argv[3], port);
    for (int sent = 0; sent < len;) {
        if (!wait_fd(fd, POLLOUT, deadline)) goto done;
        ssize_t n = send(fd, request + sent, len - sent, MSG_NOSIGNAL);
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (n <= 0) goto done;
        sent += (int)n;
    }
    char response[512];
    size_t used = 0;
    while (used < sizeof(response) - 1) {
        if (!wait_fd(fd, POLLIN, deadline)) goto done;
        ssize_t n = recv(fd, response + used, sizeof(response) - 1 - used, 0);
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) continue;
        if (n <= 0) goto done;
        used += (size_t)n;
        response[used] = '\0';
        char *newline = memchr(response, '\n', used);
        if (newline) {
            /* Any valid HTTP status demonstrates reachability, including 401
             * and 405. Never follow a redirect or interpret a response body. */
            reachable = used >= 14 && (!memcmp(response, "HTTP/1.0 ", 9) || !memcmp(response, "HTTP/1.1 ", 9)) &&
                response[9] >= '1' && response[9] <= '5' &&
                response[10] >= '0' && response[10] <= '9' &&
                response[11] >= '0' && response[11] <= '9' && response[12] == ' ' &&
                strstr(response, "\r\n") == newline - 1;
            break;
        }
    }
done:
    close(fd);
    printf("reachable=%d\n", reachable);
    return 0;
}
