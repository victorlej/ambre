/* Ambre : ce que voit le gestionnaire réseau de Steam (CNetworkDeviceManagerWin32).
 * Compiler : x86_64-w64-mingw32-gcc -O1 -o netcheck.exe netcheck.c -liphlpapi -lws2_32
 * Lancer, Steam fermé, dans une bouteille jetable : WINEPREFIX=/tmp/bouteille-test wine netcheck.exe
 * Steam appelle GetAdaptersAddresses(AF_INET, 0x96) : il faut « -> 0 » et une carte oper=1 avec une
 * IPv4, dont l'index est celui de GetBestInterface. Sinon, Steam attend 20 s le réseau. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <stdio.h>
#include <stdlib.h>
int main(void){
  DWORD best=0, r=GetBestInterface(0x08080808, &best);
  printf("GetBestInterface(8.8.8.8) -> ret=%u index=%u\n", (unsigned)r, (unsigned)best); fflush(stdout);
  ULONG sz=0x10000; IP_ADAPTER_ADDRESSES *a=malloc(sz);
  r=GetAdaptersAddresses(AF_INET,0x96,NULL,a,&sz);
  printf("GetAdaptersAddresses -> %u\n", (unsigned)r); fflush(stdout);
  if(r) return 1;
  for(IP_ADAPTER_ADDRESSES *p=a;p;p=p->Next){
    unsigned ip=0;
    for(IP_ADAPTER_UNICAST_ADDRESS *u=p->FirstUnicastAddress;u;u=u->Next)
      if(u->Address.lpSockaddr && u->Address.lpSockaddr->sa_family==AF_INET){ ip=ntohl(((struct sockaddr_in*)u->Address.lpSockaddr)->sin_addr.s_addr); break; }
    printf("idx=%-3u type=%-3u oper=%u ipv4=%u.%u.%u.%u gw=%s name=%s\n", (unsigned)p->IfIndex, (unsigned)p->IfType, (unsigned)p->OperStatus,
      ip>>24,(ip>>16)&255,(ip>>8)&255,ip&255, p->FirstGatewayAddress?"oui":"non", p->AdapterName?p->AdapterName:"?");
    fflush(stdout);
  }
  return 0;
}
