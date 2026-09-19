#define TIERNEST_NETWATCH_TEST
#include "../native/netwatch.c"
#include <assert.h>

static unsigned char packet[512] __attribute__((aligned(8)));
static struct nlmsghdr *message(unsigned type, size_t payload) {
    memset(packet, 0, sizeof(packet));
    struct nlmsghdr *h = (struct nlmsghdr *)packet;
    h->nlmsg_type = type; h->nlmsg_len = NLMSG_LENGTH(payload);
    return h;
}
static void add_attr(struct nlmsghdr *h, unsigned type, const void *data, size_t size) {
    struct nlattr *a = (struct nlattr *)(packet + NLMSG_ALIGN(h->nlmsg_len));
    a->nla_type = type; a->nla_len = NLA_HDRLEN + size;
    memcpy((char *)a + NLA_HDRLEN, data, size);
    h->nlmsg_len = NLMSG_ALIGN(h->nlmsg_len) + NLA_ALIGN(a->nla_len);
}
int main(void) {
    struct nlmsghdr *h = message(RTM_NEWLINK, sizeof(struct ifinfomsg));
    struct ifinfomsg *link = NLMSG_DATA(h);
    link->ifi_index = 700; link->ifi_flags = IFF_UP | IFF_RUNNING;
    unsigned char carrier = 1;
    add_attr(h, IFLA_IFNAME, "wlan0", 6);
    add_attr(h, IFLA_CARRIER, &carrier, 1);
    assert(route_event(h));
    assert(!route_event(h)); /* Ordinary redundant link messages do not wake shell. */
    link->ifi_flags = 0;
    assert(route_event(h)); /* Carrier down. */
    assert(!route_event(h));
    assert(wifi_name("wlan12") && !wifi_name("wlan") && !wifi_name("wlan0.bad"));

    h = message(RTM_NEWADDR, sizeof(struct ifaddrmsg));
    struct ifaddrmsg *addr = NLMSG_DATA(h);
    addr->ifa_index = 700; addr->ifa_family = AF_INET;
    assert(route_event(h));
    addr->ifa_index = 9999;
    assert(!route_event(h)); /* Unrelated mobile/VPN interface. */

    h = message(RTM_NEWROUTE, sizeof(struct rtmsg));
    struct rtmsg *route = NLMSG_DATA(h);
    route->rtm_family = AF_INET; route->rtm_type = RTN_UNICAST;
    uint32_t index = 700;
    add_attr(h, RTA_OIF, &index, sizeof(index));
    assert(route_event(h));
    route->rtm_dst_len = 24;
    assert(!route_event(h)); /* TierNest route mirrors cannot feed back into the watcher. */

    h = message(35, GENL_HDRLEN);
    struct genlmsghdr *event = NLMSG_DATA(h);
    add_attr(h, NL80211_ATTR_IFINDEX, &index, sizeof(index));
    for (unsigned i = 0; i < 3; i++) {
        event->cmd = (unsigned[]){NL80211_CMD_CONNECT, NL80211_CMD_ROAM, NL80211_CMD_DISCONNECT}[i];
        assert(mlme_event(h, 35));
    }
    event->cmd = NL80211_CMD_NEW_SCAN_RESULTS;
    assert(!mlme_event(h, 35)); /* System scans are not connection changes. */
    assert(!mlme_event(h, 36));

    h = message(RTM_NEWLINK, 0);
    assert(!route_event(h));
    assert(!message_valid(h, NLMSG_HDRLEN - 1));
    h->nlmsg_len = 500;
    assert(!message_valid(h, 100));
    h = message(35, 0);
    assert(!mlme_event(h, 35));
    h = message(RTM_NEWROUTE, sizeof(struct rtmsg));
    route = NLMSG_DATA(h); route->rtm_family = AF_INET; route->rtm_type = RTN_UNICAST;
    add_attr(h, RTA_OIF, &index, sizeof(index));
    struct nlattr *broken = (struct nlattr *)RTM_RTA(route);
    broken->nla_len = 0;
    assert(!route_event(h));
    broken->nla_len = 600;
    assert(!route_event(h));
    puts("Wi-Fi event parsing: connect, roam, disconnect, route filtering and malformed messages passed.");
}
