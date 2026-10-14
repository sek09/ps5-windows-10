/* bright.exe: brightness slider for the XP tray (next to the clock).
 * XP cannot dim the screen itself: the level is applied on the PS5 Linux side by brightd.py, which XP reaches at
 * 10.0.2.2:4450 through QEMU user networking. Left-click the sun icon for the slider, right-click to exit. */
#define _WIN32_WINNT 0x0501
#define _WIN32_IE 0x0600
#include <winsock2.h>
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define WM_TRAY (WM_APP + 1)
#define ID_SLIDER 100
#define ID_EXIT 200
#define HOST "10.0.2.2"
#define PORT 4450

static HWND hMain, hPopup, hSlider, hLabel;
static NOTIFYICONDATA nid;
static int level = 100, sent = -1;

/* One short request to brightd.py; returns the reply length (or -1). */
static int ask(const char *cmd, char *reply, int cap)
{
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a;
    int n = -1;
    if (s == INVALID_SOCKET) return -1;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(PORT);
    a.sin_addr.s_addr = inet_addr(HOST);
    if (connect(s, (struct sockaddr *)&a, sizeof(a)) == 0) {
        send(s, cmd, (int)strlen(cmd), 0);
        n = recv(s, reply, cap - 1, 0);
        if (n >= 0) reply[n] = 0;
    }
    closesocket(s);
    return n;
}

static void update_label(void)
{
    char t[64];
    sprintf(t, "Brightness: %d%%", level);
    SetWindowText(hLabel, t);
    sprintf(nid.szTip, "Brightness %d%%", level);
    Shell_NotifyIcon(NIM_MODIFY, &nid);
}

/* 16x16 sun icon drawn in code: a disc with eight rays, alpha-blended edges. */
static HICON make_sun(void)
{
    BITMAPV5HEADER bi;
    void *bits;
    HDC dc = GetDC(NULL);
    HBITMAP color, mask;
    ICONINFO ii;
    HICON ic;
    int x, y;
    const double PI = 3.14159265358979;
    memset(&bi, 0, sizeof(bi));
    bi.bV5Size = sizeof(bi); bi.bV5Width = 16; bi.bV5Height = -16; bi.bV5Planes = 1; bi.bV5BitCount = 32;
    bi.bV5Compression = BI_BITFIELDS;
    bi.bV5RedMask = 0x00FF0000; bi.bV5GreenMask = 0x0000FF00; bi.bV5BlueMask = 0x000000FF; bi.bV5AlphaMask = 0xFF000000;
    color = CreateDIBSection(dc, (BITMAPINFO *)&bi, DIB_RGB_COLORS, &bits, NULL, 0);
    ReleaseDC(NULL, dc);
    for (y = 0; y < 16; y++)
        for (x = 0; x < 16; x++) {
            double dx = x - 7.5, dy = y - 7.5, d = sqrt(dx * dx + dy * dy), a = 0;
            double k = fmod(atan2(dy, dx) + PI + PI / 8, PI / 4) - PI / 8;
            if (d <= 4.0) a = 1;
            else if (d <= 4.8) a = 4.8 - d;
            else if (d >= 5.6 && d <= 7.6 && fabs(k * d) < 0.75) a = 1;
            /* premultiplied ARGB: warm yellow */
            ((DWORD *)bits)[y * 16 + x] = a > 0 ?
                ((DWORD)(a * 255) << 24) | ((DWORD)(a * 255) << 16) | ((DWORD)(a * 190) << 8) : 0;
        }
    mask = CreateBitmap(16, 16, 1, 1, NULL);
    ii.fIcon = TRUE; ii.xHotspot = ii.yHotspot = 0; ii.hbmMask = mask; ii.hbmColor = color;
    ic = CreateIconIndirect(&ii);
    DeleteObject(color); DeleteObject(mask);
    return ic;
}

static void show_popup(void)
{
    RECT wa;
    int w = 250, h = 74;
    char r[64];
    /* Re-read the level: the keyboard brightness keys change it on the Linux side too. */
    if (ask("GET\n", r, sizeof(r)) > 0) {
        int l = (int)(atof(r) * 100 + 0.5);
        if (l >= 10 && l <= 100) {
            level = sent = l;
            SendMessage(hSlider, TBM_SETPOS, TRUE, level);
            update_label();
        }
    }
    SystemParametersInfo(SPI_GETWORKAREA, 0, &wa, 0);
    SetWindowPos(hPopup, HWND_TOPMOST, wa.right - w - 8, wa.bottom - h - 8, w, h, SWP_SHOWWINDOW);
    SetForegroundWindow(hPopup);
    SetFocus(hSlider);
}

static LRESULT CALLBACK PopupProc(HWND hw, UINT m, WPARAM wp, LPARAM lp)
{
    switch (m) {
    case WM_HSCROLL:
        level = (int)SendMessage(hSlider, TBM_GETPOS, 0, 0);
        update_label();
        SetTimer(hw, 1, 60, NULL);          /* debounce: send at most every 60 ms while dragging */
        return 0;
    case WM_TIMER: {
        char cmd[32], r[64];
        KillTimer(hw, 1);
        if (level != sent) {
            sprintf(cmd, "SET %d.%02d\n", level / 100, level % 100);
            if (ask(cmd, r, sizeof(r)) > 0) sent = level;
        }
        return 0;
    }
    case WM_ACTIVATE:
        if (LOWORD(wp) == WA_INACTIVE) ShowWindow(hw, SW_HIDE);
        return 0;
    case WM_CTLCOLORSTATIC:
        SetBkMode((HDC)wp, TRANSPARENT);
        return (LRESULT)GetSysColorBrush(COLOR_BTNFACE);
    }
    return DefWindowProc(hw, m, wp, lp);
}

static LRESULT CALLBACK MainProc(HWND hw, UINT m, WPARAM wp, LPARAM lp)
{
    if (m == WM_TRAY) {
        if (lp == WM_LBUTTONUP) show_popup();
        else if (lp == WM_RBUTTONUP) {
            POINT p;
            HMENU menu = CreatePopupMenu();
            AppendMenu(menu, MF_STRING, ID_EXIT, "Exit brightness slider");
            GetCursorPos(&p);
            SetForegroundWindow(hw);
            TrackPopupMenu(menu, TPM_RIGHTBUTTON, p.x, p.y, 0, hw, NULL);
            DestroyMenu(menu);
        }
        return 0;
    }
    if (m == WM_COMMAND && LOWORD(wp) == ID_EXIT) {
        Shell_NotifyIcon(NIM_DELETE, &nid);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProc(hw, m, wp, lp);
}

int WINAPI WinMain(HINSTANCE hi, HINSTANCE prev, LPSTR cl, int show)
{
    WSADATA wsa;
    WNDCLASS wc;
    INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_BAR_CLASSES };
    MSG msg;
    char r[64];
    HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);

    CreateMutex(NULL, TRUE, "PS5XPBrightnessSlider");
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    InitCommonControlsEx(&icc);

    memset(&wc, 0, sizeof(wc));
    wc.hInstance = hi;
    wc.lpfnWndProc = MainProc; wc.lpszClassName = "BrightMain";
    RegisterClass(&wc);
    wc.lpfnWndProc = PopupProc; wc.lpszClassName = "BrightPopup";
    wc.hbrBackground = GetSysColorBrush(COLOR_BTNFACE); wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClass(&wc);

    hMain = CreateWindow("BrightMain", "Brightness", 0, 0, 0, 0, 0, NULL, NULL, hi, NULL);
    hPopup = CreateWindowEx(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, "BrightPopup", "", WS_POPUP | WS_BORDER,
                            0, 0, 250, 74, NULL, NULL, hi, NULL);
    hLabel = CreateWindow("STATIC", "", WS_CHILD | WS_VISIBLE, 12, 8, 220, 18, hPopup, NULL, hi, NULL);
    hSlider = CreateWindow(TRACKBAR_CLASS, "", WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_NOTICKS,
                           6, 30, 236, 32, hPopup, (HMENU)ID_SLIDER, hi, NULL);
    SendMessage(hLabel, WM_SETFONT, (WPARAM)font, TRUE);
    SendMessage(hSlider, TBM_SETRANGE, TRUE, MAKELONG(10, 100));
    SendMessage(hSlider, TBM_SETPAGESIZE, 0, 10);
    SendMessage(hSlider, TBM_SETLINESIZE, 0, 5);

    if (ask("GET\n", r, sizeof(r)) > 0) {
        level = (int)(atof(r) * 100 + 0.5);
        if (level < 10 || level > 100) level = 100;
        sent = level;
    }
    SendMessage(hSlider, TBM_SETPOS, TRUE, level);

    memset(&nid, 0, sizeof(nid));
    nid.cbSize = NOTIFYICONDATA_V2_SIZE;
    nid.hWnd = hMain; nid.uID = 1; nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    nid.uCallbackMessage = WM_TRAY; nid.hIcon = make_sun();
    Shell_NotifyIcon(NIM_ADD, &nid);
    update_label();

    while (GetMessage(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    WSACleanup();
    return 0;
}
