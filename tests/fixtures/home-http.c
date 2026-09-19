/* Synthetic integration peer, used only inside disposable network namespaces. */
#include <arpa/inet.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    signal(SIGPIPE, SIG_IGN);
    int fd = socket(AF_INET, SOCK_STREAM, 0), yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr = { .sin_family = AF_INET, .sin_port = htons(18080) };
    if (inet_pton(AF_INET, argv[1], &addr.sin_addr) != 1) return 2;
    if (!strcmp(argv[2], "client")) {
        if (connect(fd, (struct sockaddr *)&addr, sizeof(addr))) return 3;
        const char *request = "HEAD / HTTP/1.1\r\nHost: fixture\r\n\r\n";
        send(fd, request, strlen(request), 0);
        char buf[128] = {0};
        int n = recv(fd, buf, sizeof(buf) - 1, 0);
        close(fd);
        return n > 0 && strstr(buf, "HTTP/1.1 200") ? 0 : 4;
    }
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || listen(fd, 8)) return 5;
    FILE *ready = fopen(argv[3], "w");
    if (!ready) return 6;
    fclose(ready);
    for (;;) {
        int client = accept(fd, NULL, NULL);
        if (client < 0) return 7;
        char request[512];
        recv(client, request, sizeof(request), 0);
        const char *reply = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n";
        if (!strcmp(argv[2], "auth")) reply = "HTTP/1.1 401 Unauthorized\r\n\r\n";
        if (!strcmp(argv[2], "malformed")) reply = "not HTTP\r\n";
        if (!strcmp(argv[2], "slow")) sleep(4);
        send(client, reply, strlen(reply), 0);
        close(client);
    }
}
