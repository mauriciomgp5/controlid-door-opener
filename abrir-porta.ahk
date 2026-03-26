#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ===== CONFIG =====
configFile := A_ScriptDir "\salas.json"
envFile := A_ScriptDir "\.env"
stateFile := A_ScriptDir "\state.ini"
salas := []
salaAtiva := 1
envVars := Map()

CarregarEnv()
CarregarSalas()
CarregarState()

; ===== TRAY MENU =====
A_TrayMenu.Delete()
A_TrayMenu.Add("Abrir Porta (Ctrl+Alt+O)", (*) => AbrirPorta())
A_TrayMenu.Add()
A_TrayMenu.Add("Salas", BuildSalasMenu())
A_TrayMenu.Add()
A_TrayMenu.Add("Adicionar Sala", (*) => AdicionarSala())
A_TrayMenu.Add("Remover Sala", BuildRemoverMenu())
A_TrayMenu.Add("Editar salas.json", (*) => Run("notepad.exe " configFile))
A_TrayMenu.Add("Recarregar Config", (*) => (CarregarSalas(), AtualizarMenus(), ToolTipMsg("Config recarregada!")))
A_TrayMenu.Add()
A_TrayMenu.Add("Sair", (*) => ExitApp())
A_TrayMenu.Default := "Abrir Porta (Ctrl+Alt+O)"
AtualizarTrayTip()

; ===== HOTKEY GLOBAL =====
^!o:: AbrirPorta()

; ===== FUNCOES =====

CarregarState() {
    global salaAtiva, stateFile, salas
    try {
        txt := FileRead(stateFile, "UTF-8")
        salaAtiva := Integer(Trim(txt))
        if salaAtiva < 1 || salaAtiva > salas.Length
            salaAtiva := 1
    } catch {
        salaAtiva := 1
    }
}

SalvarState() {
    global salaAtiva, stateFile
    try {
        f := FileOpen(stateFile, "w", "UTF-8")
        f.Write(String(salaAtiva))
        f.Close()
    }
}

CarregarEnv() {
    global envVars, envFile
    envVars := Map()
    try {
        txt := FileRead(envFile, "UTF-8")
        loop parse txt, "`n", "`r" {
            line := Trim(A_LoopField)
            if line = "" || SubStr(line, 1, 1) = "#"
                continue
            pos := InStr(line, "=")
            if pos {
                key := Trim(SubStr(line, 1, pos - 1))
                val := Trim(SubStr(line, pos + 1))
                envVars[key] := val
            }
        }
    } catch as e {
        ToolTipMsg("Erro ao carregar .env: " e.Message)
    }
}

CarregarSalas() {
    global salas, salaAtiva, configFile
    try {
        txt := FileRead(configFile, "UTF-8")
        salas := Jxon_Load(&txt)
        if salaAtiva > salas.Length
            salaAtiva := 1
    } catch as e {
        salas := []
        ToolTipMsg("Erro ao carregar salas.json: " e.Message)
    }
}

AbrirPorta() {
    global salas, salaAtiva
    if salas.Length = 0 {
        ToolTipMsg("Nenhuma sala configurada!")
        return
    }
    sala := salas[salaAtiva]
    try {
        ; Login (credenciais do .env)
        loginUser := envVars.Has("CONTROLID_LOGIN") ? envVars["CONTROLID_LOGIN"] : "admin"
        loginPass := envVars.Has("CONTROLID_PASSWORD") ? envVars["CONTROLID_PASSWORD"] : ""
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("POST", "http://" sala["ip"] "/login.fcgi", false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.Send('{"login":"' loginUser '","password":"' loginPass '"}')
        resp := http.ResponseText

        if !InStr(resp, "session") {
            ToolTipMsg("Falha login - " sala["nome"])
            return
        }
        RegExMatch(resp, '"session"\s*:\s*"([^"]+)"', &m)
        session := m[1]

        ; Abrir porta
        http2 := ComObject("WinHttp.WinHttpRequest.5.1")
        http2.Open("POST", "http://" sala["ip"] "/execute_actions.fcgi?session=" session, false)
        http2.SetRequestHeader("Content-Type", "application/json")
        http2.Send('{"actions":[{"action":"' sala["action"] '","parameters":"' sala["parameters"] '"}]}')

        ; Beep de confirmacao
        http3 := ComObject("WinHttp.WinHttpRequest.5.1")
        http3.Open("POST", "http://" sala["ip"] "/buzzer_buzz.fcgi?session=" session, false)
        http3.SetRequestHeader("Content-Type", "application/json")
        http3.Send('{"frequency":4000,"duty_cycle":50,"timeout":200}')

        ToolTipMsg(sala["nome"] " - Porta aberta!")
    } catch as e {
        ToolTipMsg("Erro: " e.Message)
    }
}

BuildSalasMenu() {
    global salas, salaAtiva
    m := Menu()
    for i, sala in salas {
        nome := sala["nome"] " (" sala["ip"] ")"
        m.Add(nome, SelecionarSala.Bind(i))
        if i = salaAtiva
            m.Check(nome)
    }
    if salas.Length = 0
        m.Add("(nenhuma sala)", (*) => 0)
    return m
}

BuildRemoverMenu() {
    global salas
    m := Menu()
    for i, sala in salas
        m.Add(sala["nome"] " (" sala["ip"] ")", RemoverSala.Bind(i))
    if salas.Length = 0
        m.Add("(nenhuma sala)", (*) => 0)
    return m
}

SelecionarSala(idx, *) {
    global salaAtiva
    salaAtiva := idx
    SalvarState()
    AtualizarMenus()
}

AtualizarMenus() {
    ; Rebuild menus recarregando o script
    Reload
}

AtualizarTrayTip() {
    global salas, salaAtiva
    if salas.Length > 0
        A_IconTip := "Porta: " salas[salaAtiva]["nome"] " (Ctrl+Alt+O)"
    else
        A_IconTip := "Abrir Porta (sem salas)"
}

AdicionarSala() {
    global configFile, salas
    mainGui := Gui("+AlwaysOnTop", "Adicionar Sala")
    mainGui.Add("Text",, "Nome da sala:")
    mainGui.Add("Edit", "w250 vNome")
    mainGui.Add("Text",, "IP do dispositivo:")
    mainGui.Add("Edit", "w250 vIp")
    mainGui.Add("Text",, "Action (sec_box / door / catra):")
    mainGui.Add("Edit", "w250 vAction", "sec_box")
    mainGui.Add("Text",, "Parameters:")
    mainGui.Add("Edit", "w250 vParams", "id=65793, reason=3")
    mainGui.Add("Button", "w250 Default", "Salvar").OnEvent("Click", (*) => SalvarNovaSala(mainGui))
    mainGui.Show()
}

SalvarNovaSala(g) {
    global configFile, salas
    dados := g.Submit()
    if dados.Nome = "" || dados.Ip = "" {
        MsgBox("Nome e IP são obrigatórios!", "Erro", "Icon!")
        return
    }
    novaSala := Map(
        "nome", dados.Nome,
        "ip", dados.Ip,
        "action", dados.Action,
        "parameters", dados.Params
    )
    salas.Push(novaSala)
    SalvarConfig()
    Reload
}

RemoverSala(idx, *) {
    global salas
    nome := salas[idx]["nome"]
    if MsgBox("Remover " nome "?",, "YesNo Icon?") = "Yes" {
        salas.RemoveAt(idx)
        SalvarConfig()
        Reload
    }
}

SalvarConfig() {
    global configFile, salas
    txt := Jxon_Dump(salas, 4)
    f := FileOpen(configFile, "w", "UTF-8")
    f.Write(txt)
    f.Close()
}

ToolTipMsg(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -2500)
}

; ===== JXON (JSON parser/writer for AHK v2) =====
; Minimal built-in JSON support

Jxon_Load(&src) {
    src := Trim(src)
    idx := 1
    return _JsonParse(src, &idx)
}

_JsonParse(src, &idx) {
    _JsonSkipWS(src, &idx)
    ch := SubStr(src, idx, 1)
    if ch = "[" {
        idx++
        arr := []
        _JsonSkipWS(src, &idx)
        if SubStr(src, idx, 1) = "]" {
            idx++
            return arr
        }
        loop {
            arr.Push(_JsonParse(src, &idx))
            _JsonSkipWS(src, &idx)
            if SubStr(src, idx, 1) = "," {
                idx++
                continue
            }
            break
        }
        idx++ ; ]
        return arr
    }
    if ch = "{" {
        idx++
        obj := Map()
        _JsonSkipWS(src, &idx)
        if SubStr(src, idx, 1) = "}" {
            idx++
            return obj
        }
        loop {
            _JsonSkipWS(src, &idx)
            key := _JsonParseString(src, &idx)
            _JsonSkipWS(src, &idx)
            idx++ ; :
            obj[key] := _JsonParse(src, &idx)
            _JsonSkipWS(src, &idx)
            if SubStr(src, idx, 1) = "," {
                idx++
                continue
            }
            break
        }
        idx++ ; }
        return obj
    }
    if ch = '"'
        return _JsonParseString(src, &idx)
    ; number / true / false / null
    RegExMatch(src, "[-\d.eE+]+|true|false|null", &m, idx)
    idx += m.Len
    val := m[0]
    if val = "true"
        return true
    if val = "false"
        return false
    if val = "null"
        return ""
    return Number(val)
}

_JsonParseString(src, &idx) {
    idx++ ; opening "
    result := ""
    loop {
        ch := SubStr(src, idx, 1)
        if ch = '"' {
            idx++
            return result
        }
        if ch = "\" {
            idx++
            esc := SubStr(src, idx, 1)
            idx++
            switch esc {
                case "n": result .= "`n"
                case "t": result .= "`t"
                case "r": result .= "`r"
                case "\": result .= "\"
                case "/": result .= "/"
                case '"': result .= '"'
                case "u":
                    hex := SubStr(src, idx, 4)
                    idx += 4
                    result .= Chr("0x" hex)
                default: result .= esc
            }
        } else {
            result .= ch
            idx++
        }
    }
}

_JsonSkipWS(src, &idx) {
    while idx <= StrLen(src) && InStr(" `t`n`r", SubStr(src, idx, 1))
        idx++
}

Jxon_Dump(obj, indent := 0, level := 0) {
    if obj is Array {
        if obj.Length = 0
            return "[]"
        items := ""
        for v in obj {
            if items != ""
                items .= ",`n"
            items .= _Indent(indent, level + 1) Jxon_Dump(v, indent, level + 1)
        }
        return "[`n" items "`n" _Indent(indent, level) "]"
    }
    if obj is Map {
        if obj.Count = 0
            return "{}"
        items := ""
        for k, v in obj {
            if items != ""
                items .= ",`n"
            items .= _Indent(indent, level + 1) '"' _JsonEscape(k) '": ' Jxon_Dump(v, indent, level + 1)
        }
        return "{`n" items "`n" _Indent(indent, level) "}"
    }
    if obj is Number
        return String(obj)
    if obj = ""
        return '""'
    return '"' _JsonEscape(String(obj)) '"'
}

_JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    return s
}

_Indent(size, level) {
    if size = 0
        return ""
    return Format("{:" size * level "}", " ")
}
