#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/ipv6.h>

char LICENSE[] SEC("license") = "GPL";

SEC("cgroup/connect4")
int khz_connect4(struct bpf_sock_addr *ctx)
{
    return 0;
}

SEC("cgroup/connect6")
int khz_connect6(struct bpf_sock_addr *ctx)
{
    return 0;
}

SEC("cgroup/sendmsg4")
int khz_sendmsg4(struct bpf_sock_addr *ctx)
{
    return 0;
}

SEC("cgroup/sendmsg6")
int khz_sendmsg6(struct bpf_sock_addr *ctx)
{
    return 0;
}
