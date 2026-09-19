/* SPDX-License-Identifier: LGPL-3.0-or-later
 * Blocking Wi-Fi event source. No periodic timer, scans, probes or log files.
 * RTNETLINK covers carrier/address/default-route changes; nl80211 MLME also
 * covers roaming between APs without an address or carrier change.
 */
#include <errno.h>
#include <linux/genetlink.h>
#include <linux/if_link.h>
#include <linux/nl80211.h>
#include <linux/rtnetlink.h>
#include <net/if.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define ATTR_DATA(a) ((const unsigned char *)(a) + NLA_HDRLEN)
#define ATTR_SIZE(a) ((int)(a)->nla_len - NLA_HDRLEN)
#define ATTR_TYPE(a) ((a)->nla_type & NLA_TYPE_MASK)
#define EACH_ATTR(a, data, size) \
    for (int left = (size), once = 1; once; once = 0) \
        for (const struct nlattr *a = (const struct nlattr *)(data); \
             left >= NLA_HDRLEN && a->nla_len >= NLA_HDRLEN && a->nla_len <= left; \
             left -= NLA_ALIGN(a->nla_len), a = (const struct nlattr *)((const char *)a + NLA_ALIGN(a->nla_len)))

struct wifi_link { unsigned index, flags; unsigned char carrier, mac[6]; bool initialized; };
static struct wifi_link links[32];

static bool wifi_name(const char *name) {
    if (strncmp(name, "wlan", 4) || !name[4]) return false;
    for (const char *p = name + 4; *p; ++p) if (*p < '0' || *p > '9') return false;
    return true;
}

static struct wifi_link *link_entry(unsigned index, bool create) {
    for (unsigned i = 0; i < 32; ++i) if (links[i].index == index && index) return &links[i];
    if (create && index) for (unsigned i = 0; i < 32; ++i) if (!links[i].index) {
        links[i].index = index;
        return &links[i];
    }
    return NULL;
}

static bool wifi_index(unsigned index) {
    char name[IF_NAMESIZE];
    if (link_entry(index, false)) return true;
    return if_indextoname(index, name) && wifi_name(name);
}

static bool message_valid(const struct nlmsghdr *h, int remaining) {
    return remaining >= (int)sizeof(*h) && h->nlmsg_len >= sizeof(*h) && h->nlmsg_len <= (unsigned)remaining;
}

static uint32_t attr_u32(const struct nlattr *a) {
    uint32_t value = 0;
    if (ATTR_SIZE(a) >= (int)sizeof(value)) memcpy(&value, ATTR_DATA(a), sizeof(value));
    return value;
}

static bool route_event(const struct nlmsghdr *h) {
    int size = (int)h->nlmsg_len - NLMSG_HDRLEN;
    if (h->nlmsg_type == RTM_NEWLINK || h->nlmsg_type == RTM_DELLINK) {
        if (size < (int)sizeof(struct ifinfomsg)) return false;
        const struct ifinfomsg *m = NLMSG_DATA(h);
        char name[IF_NAMESIZE] = {0};
        unsigned char carrier = 0, mac[6] = {0};
        bool has_carrier = false, has_mac = false;
        EACH_ATTR(a, IFLA_RTA(m), size - NLMSG_ALIGN(sizeof(*m))) {
            if (ATTR_TYPE(a) == IFLA_IFNAME && ATTR_SIZE(a) > 0 && ATTR_SIZE(a) <= IF_NAMESIZE) {
                memcpy(name, ATTR_DATA(a), ATTR_SIZE(a)); name[IF_NAMESIZE - 1] = 0;
            }
            if (ATTR_TYPE(a) == IFLA_CARRIER && ATTR_SIZE(a) >= 1) { carrier = *ATTR_DATA(a); has_carrier = true; }
            if (ATTR_TYPE(a) == IFLA_ADDRESS && ATTR_SIZE(a) == 6) { memcpy(mac, ATTR_DATA(a), 6); has_mac = true; }
        }
        if (!wifi_name(name) && !wifi_index(m->ifi_index)) return false;
        struct wifi_link *entry = link_entry(m->ifi_index, true);
        if (!entry) return true;
        if (h->nlmsg_type == RTM_DELLINK) { memset(entry, 0, sizeof(*entry)); return true; }
        if (!has_carrier) carrier = entry->carrier;
        if (!has_mac) memcpy(mac, entry->mac, 6);
        unsigned flags = m->ifi_flags & (IFF_UP | IFF_RUNNING | 0x10000u); /* LOWER_UP */
        bool changed = !entry->initialized || flags != entry->flags || carrier != entry->carrier || memcmp(mac, entry->mac, 6);
        entry->initialized = true; entry->flags = flags; entry->carrier = carrier; memcpy(entry->mac, mac, 6);
        return changed;
    }
    if (h->nlmsg_type == RTM_NEWADDR || h->nlmsg_type == RTM_DELADDR) {
        if (size < (int)sizeof(struct ifaddrmsg)) return false;
        const struct ifaddrmsg *m = NLMSG_DATA(h);
        return m->ifa_family == AF_INET && wifi_index(m->ifa_index);
    }
    if (h->nlmsg_type == RTM_NEWROUTE || h->nlmsg_type == RTM_DELROUTE) {
        if (size < (int)sizeof(struct rtmsg)) return false;
        const struct rtmsg *m = NLMSG_DATA(h);
        if (m->rtm_family != AF_INET || m->rtm_dst_len != 0 || m->rtm_type != RTN_UNICAST) return false;
        EACH_ATTR(a, RTM_RTA(m), size - NLMSG_ALIGN(sizeof(*m))) {
            if (ATTR_TYPE(a) == RTA_OIF && wifi_index(attr_u32(a))) return true;
        }
    }
    return false;
}

static bool mlme_event(const struct nlmsghdr *h, unsigned family) {
    if (h->nlmsg_type != family || h->nlmsg_len < NLMSG_LENGTH(GENL_HDRLEN)) return false;
    const struct genlmsghdr *m = NLMSG_DATA(h);
    if (m->cmd != NL80211_CMD_CONNECT && m->cmd != NL80211_CMD_DISCONNECT && m->cmd != NL80211_CMD_ROAM) return false;
    EACH_ATTR(a, (const char *)m + GENL_HDRLEN, h->nlmsg_len - NLMSG_HDRLEN - GENL_HDRLEN) {
        if (ATTR_TYPE(a) == NL80211_ATTR_IFINDEX && wifi_index(attr_u32(a))) return true;
    }
    return false;
}

static int open_netlink(int protocol, unsigned groups) {
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, protocol);
    if (fd < 0) return -1;
    struct sockaddr_nl local = { .nl_family = AF_NETLINK, .nl_groups = groups };
    int buffer = 262144;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buffer, sizeof(buffer));
    if (bind(fd, (struct sockaddr *)&local, sizeof(local))) { close(fd); return -1; }
    return fd;
}

/* Receive kernel messages only, and fail on truncation/overflow instead of
 * silently leaving the core paused after a lost disconnect event. */
static int receive_kernel(int fd, void *data, size_t size) {
    struct sockaddr_nl sender = {0};
    struct iovec iov = { .iov_base = data, .iov_len = size };
    struct msghdr message = { .msg_name = &sender, .msg_namelen = sizeof(sender), .msg_iov = &iov, .msg_iovlen = 1 };
    ssize_t count = recvmsg(fd, &message, MSG_DONTWAIT);
    if (count < 0) return -1;
    if (message.msg_flags & MSG_TRUNC) { errno = ENOBUFS; return -1; }
    if (sender.nl_pid != 0) return 0;
    return (int)count;
}

static int subscribe_mlme(int fd) {
    struct { struct nlmsghdr h; struct genlmsghdr g; struct nlattr a; char name[8]; } request = {
        .h = { .nlmsg_len = NLMSG_LENGTH(GENL_HDRLEN + NLA_HDRLEN + 8), .nlmsg_type = GENL_ID_CTRL, .nlmsg_flags = NLM_F_REQUEST, .nlmsg_seq = 1 },
        .g = { .cmd = CTRL_CMD_GETFAMILY, .version = 1 },
        .a = { .nla_len = NLA_HDRLEN + 8, .nla_type = CTRL_ATTR_FAMILY_NAME }, .name = "nl80211"
    };
    struct sockaddr_nl kernel = { .nl_family = AF_NETLINK };
    if (sendto(fd, &request, request.h.nlmsg_len, 0, (struct sockaddr *)&kernel, sizeof(kernel)) < 0) return -1;
    struct pollfd waiter = { .fd = fd, .events = POLLIN };
    if (poll(&waiter, 1, 2000) <= 0) { errno = ETIMEDOUT; return -1; }
    unsigned char data[32768] __attribute__((aligned(8)));
    int count = receive_kernel(fd, data, sizeof(data));
    if (count < 0) return -1;
    unsigned family = 0, group = 0;
    for (struct nlmsghdr *h = (struct nlmsghdr *)data; message_valid(h, count); h = NLMSG_NEXT(h, count)) {
        if (h->nlmsg_type == NLMSG_ERROR) { errno = EOPNOTSUPP; return -1; }
        if (h->nlmsg_len < NLMSG_LENGTH(GENL_HDRLEN)) continue;
        EACH_ATTR(a, (char *)NLMSG_DATA(h) + GENL_HDRLEN, h->nlmsg_len - NLMSG_HDRLEN - GENL_HDRLEN) {
            if (ATTR_TYPE(a) == CTRL_ATTR_FAMILY_ID && ATTR_SIZE(a) >= 2) { uint16_t id; memcpy(&id, ATTR_DATA(a), 2); family = id; }
            if (ATTR_TYPE(a) != CTRL_ATTR_MCAST_GROUPS) continue;
            EACH_ATTR(item, ATTR_DATA(a), ATTR_SIZE(a)) {
                bool mlme = false; unsigned id = 0;
                EACH_ATTR(field, ATTR_DATA(item), ATTR_SIZE(item)) {
                    if (ATTR_TYPE(field) == CTRL_ATTR_MCAST_GRP_NAME && ATTR_SIZE(field) == 5 && !memcmp(ATTR_DATA(field), "mlme", 5)) mlme = true;
                    if (ATTR_TYPE(field) == CTRL_ATTR_MCAST_GRP_ID) id = attr_u32(field);
                }
                if (mlme) group = id;
            }
        }
    }
    if (!family || !group) { errno = EOPNOTSUPP; return -1; }
    if (setsockopt(fd, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &group, sizeof(group))) return -1;
    return (int)family;
}

static int64_t millis(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

#ifndef TIERNEST_NETWATCH_TEST
int main(int argc, char **argv) {
    bool check = argc == 2 && !strcmp(argv[1], "--check");
    if (argc > 1 && !check) { fprintf(stderr, "Usage: tiernest-netwatch [--check]\n"); return 2; }
    pid_t parent = getppid();
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) || parent != getppid()) return 1;
    int route = open_netlink(NETLINK_ROUTE, RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV4_ROUTE);
    int wifi = open_netlink(NETLINK_GENERIC, 0);
    int family = wifi < 0 ? -1 : subscribe_mlme(wifi);
    if (route < 0 || family < 0) { perror("Wi-Fi event subscription"); if (route >= 0) close(route); if (wifi >= 0) close(wifi); return 1; }
    if (check) { close(route); close(wifi); return 0; }
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("ready");
    struct pollfd fds[] = { { .fd = route, .events = POLLIN }, { .fd = wifi, .events = POLLIN } };
    int64_t deadline = 0;
    for (;;) {
        int timeout = deadline ? (int)(deadline - millis()) : -1;
        if (deadline && timeout < 0) timeout = 0;
        int rc = poll(fds, 2, timeout);
        if (rc < 0) { if (errno == EINTR) continue; break; }
        for (int i = 0; i < 2; ++i) {
            if (fds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) { errno = EIO; goto failed; }
            if (!(fds[i].revents & POLLIN)) continue;
            unsigned char data[32768] __attribute__((aligned(8)));
            int count = receive_kernel(fds[i].fd, data, sizeof(data));
            if (count < 0) { if (errno == EINTR || errno == EAGAIN) continue; goto failed; }
            for (struct nlmsghdr *h = (struct nlmsghdr *)data; message_valid(h, count); h = NLMSG_NEXT(h, count)) {
                if (h->nlmsg_type == NLMSG_ERROR || h->nlmsg_type == NLMSG_OVERRUN) { errno = EIO; goto failed; }
                bool changed = i == 0 ? route_event(h) : mlme_event(h, family);
                /* First-event deadline bounds debounce even during a burst. */
                if (changed && !deadline) deadline = millis() + 500;
            }
        }
        if (deadline && millis() >= deadline) {
            /* One unread notification is enough: the shell takes a fresh
             * snapshot. Coalesce changes while it is settling/reconciling. */
            int queued = 0;
            if (ioctl(STDOUT_FILENO, FIONREAD, &queued) < 0 || queued == 0) puts("change");
            deadline = 0;
        }
    }
failed:
    perror("Wi-Fi event listener stopped");
    close(route); close(wifi);
    return 1;
}
#endif
