_G.originalTerm = term
_G.Srunix = {
    version = "0.4.0",
    hostname = "srunix",
    user = "root",
    uid = 0,
    gid = 0,
    home = "/srunix/home/root",
    cwd = "C:\\srunix\\home\\root\\",
    env = {},
}

Srunix.Users = dofile("/srunix/kernel/users.lua")
Srunix.VFS = dofile("/srunix/kernel/vfs.lua")
Srunix.SB = dofile("/srunix/kernel/screen.lua")
Srunix.Utils = dofile("/srunix/kernel/utils.lua")

Srunix.env = {
    Srunix = Srunix,
    VFS = Srunix.VFS,
    SB = Srunix.SB,
    Utils = Srunix.Utils,
    Users = Srunix.Users,
    print = function(...)
        Srunix.SB.addLine(table.concat({...}, "\t"))
    end,
    write = write,
    sleep = sleep,
    textToNumber = Srunix.Utils.textToNumber,
    argToNumber = Srunix.Utils.argToNumber,
}

dofile("/srunix/kernel/shell.lua")
