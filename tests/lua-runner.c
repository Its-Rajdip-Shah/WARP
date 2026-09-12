/* Optional macOS test host using Hammerspoon's bundled Lua; no GUI APIs loaded. */
#include <stdio.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
int main(int argc, char **argv) {
  lua_State *L=luaL_newstate(); luaL_openlibs(L);
  int syntax=argc>1 && strcmp(argv[1],"--syntax")==0;
  int result=0;
  for(int i=syntax?2:1;i<argc;i++) {
    if(luaL_loadfile(L,argv[i]) || (!syntax && lua_pcall(L,0,LUA_MULTRET,0))) {
      fprintf(stderr,"%s: %s\n",argv[i],lua_tostring(L,-1)); result=1;
    }
    lua_settop(L,0);
  }
  lua_close(L); return result;
}
