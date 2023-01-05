VERSION 5.00
Begin VB.UserControl pdButtonToolbox 
   Appearance      =   0  'Flat
   BackColor       =   &H80000005&
   ClientHeight    =   3600
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   4800
   ClipBehavior    =   0  'None
   DrawStyle       =   5  'Transparent
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   HasDC           =   0   'False
   HitBehavior     =   0  'None
   PaletteMode     =   4  'None
   ScaleHeight     =   240
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   320
   ToolboxBitmap   =   "pdButtonToolbox.ctx":0000
End
Attribute VB_Name = "pdButtonToolbox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Toolbox Button control
'Copyright 2014-2023 by Tanner Helland
'Created: 19/October/14
'Last updated: 12/December/21
'Last update: allow caller to specify resampling method when assigning button images
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this toolbox button control, specifically:
'
' 1) Why make a separate control for toolbox buttons?  I could add a style property to the regular PD button, but I don't
'     like the complications that introduces.  "Do one thing and do it well" is the idea with PD user controls.
' 2) High DPI settings are handled automatically.
' 3) A hand cursor is automatically applied, and clicks are returned via the Click event.
' 4) Coloration is automatically handled by PD's internal theming engine.
' 5) This button does not support text, by design.  It is image-only.
' 6) This button does not automatically set its Value property when clicked.  It simply raises a Click() event.  This is
'     by design to make it easier to toggle state in the toolbox maintenance code.
'
'Unless otherwise noted, all source code in this file is shared under a simplified BSD license.
' Full license details are available in the LICENSE.md file, or at https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

'This control really only needs one event raised - Click.  Note that I've added a Shift parameter;
' this allows for e.g. Ctrl+Click and Shift+Click events to be handled more naturally.
Public Event Click(ByVal Shift As ShiftConstants)

'Because VB focus events are wonky, especially when we use CreateWindow within a UC, this control raises its own
' specialized focus events.  If you need to track focus, use these instead of the default VB functions.
Public Event GotFocusAPI()
Public Event LostFocusAPI()
Public Event SetCustomTabTarget(ByVal shiftTabWasPressed As Boolean, ByRef newTargetHwnd As Long)

'Current button state; TRUE if down, FALSE if up.  Note that this may not correspond with mouse state, depending on
' button properties (buttons can toggle in various ways).
Private m_ButtonState As Boolean

'Three distinct button images - normal, hover, and disabled - are auto-generated by this control, and stored to a
' single sprite-sheet style DIB.  The caller must supply the normal image as a reference.
' (Also, since this control doesn't support text captions, you *must* supply an image!)
Private m_ButtonWidth As Long, m_ButtonHeight As Long

'NEW TEST: use image caching for standard images
Private Enum PD_SpriteType
    st_Normal = 0
    st_Hover = 1
    st_Disabled = 2
    st_NormalPressed = 3
    st_HoverPressed = 4
    st_DisabledPressed = 5
End Enum

#If False Then
    Private Const st_Normal = 0, st_Hover = 1, st_Disabled = 2, st_NormalPressed = 3, st_HoverPressed = 4, st_DisabledPressed = 5
#End If

Private m_SpriteHandles() As Long

'As of Feb 2015, this control also supports unique images when depressed.  This feature is optional!
Private m_ButtonImagesPressed As Boolean

'(x, y) position of the button image.  This is auto-calculated by the control.
Private btImageCoords As PointAPI

'Current back color.  Because this control sits on a variety of places in PD (like the canvas status bar), its BackColor
' sometimes needs to be set manually.  (Note that this custom value will not be used unless m_UseCustomBackColor is TRUE!)
Private m_BackColor As OLE_COLOR, m_UseCustomBackColor As Boolean

'AutoToggle mode allows the button to operate as a normal button (e.g. no persistent value)
Private m_AutoToggle As Boolean

'StickyToggle mode allows the button to operate as a checkbox (e.g. a persistent value, that switches on every click)
Private m_StickyToggle As Boolean

'In some circumstances, an image alone is sufficient for indicating "pressed" state.
' This value tells the control to *not* render a custom highlight state when a button is depressed.
Private m_DontHighlightDownState As Boolean

'In 2019, I added a "flash" action to this button; the search bar uses this to draw attention to a given tool when it
' is activated via the search bar.
Private WithEvents m_FlashTimer As pdTimer
Attribute m_FlashTimer.VB_VarHelpID = -1
Private m_FlashCount As Long, m_FlashTimeElapsed As Long, m_FlashLength As Long

'User control support class.  Historically, many classes (and associated subclassers) were required by each user control,
' but I've since wrapped these into a single central support class.
Private WithEvents ucSupport As pdUCSupport
Attribute ucSupport.VB_VarHelpID = -1

'Local list of themable colors.  This list includes all potential colors used by the control, regardless of state change
' or internal control settings.  The list is updated by calling the UpdateColorList function.
' (Note also that this list does not include variants, e.g. "BorderColor" vs "BorderColor_Hovered".  Variant values are
'  automatically calculated by the color management class, and they are retrieved by passing boolean modifiers to that
'  class, rather than treating every imaginable variant as a separate constant.)
Private Enum PDTOOLBUTTON_COLOR_LIST
    [_First] = 0
    PDTB_Background = 0
    PDTB_ButtonFill = 1
    PDTB_Border = 2
    [_Last] = 2
    [_Count] = 3
End Enum

'Color retrieval and storage is handled by a dedicated class; this allows us to optimize theme interactions,
' without worrying about the details locally.
Private m_Colors As pdThemeColors

Public Function GetControlType() As PD_ControlType
    GetControlType = pdct_ButtonToolbox
End Function

Public Function GetControlName() As String
    GetControlName = UserControl.Extender.Name
End Function

'This toolbox button control is designed to be used in a "radio button"-like system, where buttons exist in a group, and the
' pressing of one results in the unpressing of any others.  For the rare circumstances where this behavior is undesirable
' (e.g. the pdCanvas status bar, where some instances of this control serve as actual buttons), the AutoToggle property can
' be set to TRUE.  This will cause the button to operate as a normal command button, which depresses on MouseDown and raises
' on MouseUp.
Public Property Get AutoToggle() As Boolean
    AutoToggle = m_AutoToggle
End Property

Public Property Let AutoToggle(ByVal newToggle As Boolean)
    m_AutoToggle = newToggle
End Property

'BackColor is an important property for this control, as it may sit on other controls whose backcolor is not guaranteed in advance.
' So we can't rely on theming alone to determine this value.
Public Property Get BackColor() As OLE_COLOR
    BackColor = m_BackColor
End Property

Public Property Let BackColor(ByVal newBackColor As OLE_COLOR)
    m_BackColor = newBackColor
    RedrawBackBuffer
End Property

'In some circumstances, an image alone is sufficient for indicating "pressed" state.  This value tells the control to *not* render a custom
' highlight state when button state is TRUE (pressed).
Public Property Get DontHighlightDownState() As Boolean
    DontHighlightDownState = m_DontHighlightDownState
End Property

Public Property Let DontHighlightDownState(ByVal newState As Boolean)
    m_DontHighlightDownState = newState
    If Value Then RedrawBackBuffer
End Property

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal newValue As Boolean)
    If (UserControl.Enabled <> newValue) Then
        UserControl.Enabled = newValue
        PropertyChanged "Enabled"
        If ucSupport.AmIVisible Then RedrawBackBuffer
    End If
End Property

Public Property Get HasFocus() As Boolean
    HasFocus = ucSupport.DoIHaveFocus()
End Property

'Sticky toggle allows this button to operate as a checkbox, where each click toggles its value.  If I was smart, I would have implemented
' the button's toggle behavior as a single property with multiple enum values, but I didn't think of it in advance, so now I'm stuck
' with this.  Do not set both StickyToggle and AutoToggle, as the button will not behave correctly.
Public Property Get StickyToggle() As Boolean
    StickyToggle = m_StickyToggle
End Property

Public Property Let StickyToggle(ByVal newValue As Boolean)
    m_StickyToggle = newValue
End Property

'hWnds aren't exposed by default
Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'Container hWnd must be exposed for external tooltip handling
Public Property Get ContainerHwnd() As Long
    ContainerHwnd = UserControl.ContainerHwnd
End Property

'The most relevant part of this control is this Value property, which is important since this button operates as a toggle.
Public Property Get Value() As Boolean
    Value = m_ButtonState
End Property

Public Property Let Value(ByVal newValue As Boolean)
    
    'Update our internal value tracker, but only if autotoggle is not active.
    ' (Autotoggle causes the button to behave like a normal command button,
    ' so there's no concept of a persistent "value".)
    If (m_ButtonState <> newValue) And (Not m_AutoToggle) Then
    
        m_ButtonState = newValue
        
        'Redraw the control to match the new state
        RedrawBackBuffer
        
        'Note that we don't raise a Click event here.  This is by design.  The toolbox handles all
        ' toggle code for these buttons, and it's more efficient to let it handle this, as it already
        ' has a detailed notion of things like program state, which affects whether buttons are clickable, etc.
        '
        'As such, the Click event is not raised for Value changes alone - only for actions initiated by actual
        ' user input.  (If you use this control anywhere *other* than the toolbox, you'll need to plan
        ' accordingly for this behavior.)
        
    End If
    
End Property

Public Property Get UseCustomBackColor() As Boolean
    UseCustomBackColor = m_UseCustomBackColor
End Property

Public Property Let UseCustomBackColor(ByVal newValue As Boolean)
    m_UseCustomBackColor = newValue
    RedrawBackBuffer
    PropertyChanged "UseCustomBackColor"
End Property

'Assign a DIB to this button.  Matching disabled and hover state DIBs are automatically generated.
' Note that you can supply an existing DIB, or a resource name.  If a source DIB is passed, you *must* still
' pass a unique resource ID.  The resource ID is used as part of the UI images cache, to ensure duplicate
' images are not cached twice.  (If loading an ID from the resource file, you can obviously skip passing
' the source DIB, however.)
Public Sub AssignImage(ByRef resName As String, Optional ByRef srcDIB As pdDIB = Nothing, Optional ByVal useImgWidth As Long = 0, Optional ByVal useImgHeight As Long = 0, Optional ByVal imgBorderSizeIfAny As Long = 0, Optional ByVal resampleAlgorithm As GP_InterpolationMode = GP_IM_HighQualityBicubic, Optional ByVal usePDResamplerInstead As PD_ResamplingFilter = rf_Automatic)
    
    If (Not PDMain.IsProgramRunning) Then Exit Sub
    
    'Load the requested resource DIB, as necessary.  (I say "as necessary" because the caller can supply the DIB as-is, too.)
    If (LenB(resName) <> 0) Then IconsAndCursors.LoadResourceToDIB resName, srcDIB, useImgWidth, useImgHeight, imgBorderSizeIfAny, resampleAlgorithm:=resampleAlgorithm, usePDResamplerInstead:=usePDResamplerInstead
    If (srcDIB Is Nothing) Then Exit Sub
    
    'Cache the width and height of the DIB; it serves as our reference measurements for subsequent blt operations.
    ' (We also check these for != 0 to verify that an image was successfully loaded.)
    m_ButtonWidth = srcDIB.GetDIBWidth
    m_ButtonHeight = srcDIB.GetDIBHeight
    
    If (m_ButtonWidth <> 0) And (m_ButtonHeight <> 0) Then
        
        'Add this image to the central UI image cache (and if no name exists, invent a random one)
        If (LenB(resName) = 0) Then resName = OS.GetArbitraryGUID()
        m_SpriteHandles(st_Normal) = UIImages.AddImage(srcDIB, resName)
        m_SpriteHandles(st_Hover) = UI_SPRITE_UNDEFINED
        m_SpriteHandles(st_Disabled) = UI_SPRITE_UNDEFINED
        
    End If
    
    'Request a control layout update, which will also calculate a centered position for the new image
    UpdateControlLayout
    If ucSupport.AmIVisible Then RedrawBackBuffer True, False
    
End Sub

'Assign an *OPTIONAL* special DIB to this button, to be used only when the button is pressed.
' Disabled and hover state are automatically generated for you.
'
'IMPORTANT NOTE!  To reduce resource usage, PD requires that this optional "pressed" image have
' identical dimensions to the primary image. This greatly simplifies layout and painting issues,
' so I do not expect to change it.
Public Sub AssignImage_Pressed(ByRef resName As String, Optional ByRef srcDIB As pdDIB, Optional ByVal useImgWidth As Long = 0, Optional ByVal useImgHeight As Long = 0, Optional ByVal imgBorderSizeIfAny As Long = 0, Optional ByVal resampleAlgorithm As GP_InterpolationMode = GP_IM_HighQualityBicubic, Optional ByVal usePDResamplerInstead As PD_ResamplingFilter = rf_Automatic)
    
    If (Not PDMain.IsProgramRunning) Then Exit Sub
    
    'Load the requested resource DIB, as necessary.  (I say "as necessary" because the caller can supply the DIB as-is, too.)
    If (LenB(resName) <> 0) Then IconsAndCursors.LoadResourceToDIB resName, srcDIB, useImgWidth, useImgHeight, imgBorderSizeIfAny, resampleAlgorithm:=resampleAlgorithm, usePDResamplerInstead:=rf_Automatic
    If (srcDIB Is Nothing) Then Exit Sub
    
    'The caller needs to have *already* assigned a default image to this button; that image is used for
    ' critical layout decisions that must be made *prior* to loading subsequent images.
    If (m_ButtonWidth <> 0) And (m_ButtonHeight <> 0) Then
        
        m_ButtonImagesPressed = True
        
        'Add this image to the central UI image cache (and if no name exists, invent a random one)
        If (LenB(resName) = 0) Then resName = OS.GetArbitraryGUID()
        m_SpriteHandles(st_NormalPressed) = UIImages.AddImage(srcDIB, resName)
        m_SpriteHandles(st_HoverPressed) = UI_SPRITE_UNDEFINED
        m_SpriteHandles(st_DisabledPressed) = UI_SPRITE_UNDEFINED
        
    End If
    
    'If the control is visible, request an immediate redraw
    If ucSupport.AmIVisible Then RedrawBackBuffer True, False
    
End Sub

'After loading the initial button DIB and creating a matching spritesheet, call this function to fill the rest of
' the spritesheet with the "glowy hovered" and "grayscale disabled" button image variants.
Private Sub GenerateVariantButtonImage_Hover(ByRef srcDIB As pdDIB, ByRef origImageName As String, Optional ByVal thisIsSpecialPressedImage As Boolean = False)
    
    'Start by building two lookup tables: one for the hovered image, and a second one for the disabled image
    Dim hLookup(0 To 255) As Byte
    
    Dim newPxColor As Long, x As Long, y As Long
    For x = 0 To 255
        newPxColor = x + UC_HOVER_BRIGHTNESS
        If (newPxColor > 255) Then newPxColor = 255
        hLookup(x) = newPxColor
    Next x
    
    'We require direct access to the source image's bytes...
    If srcDIB.GetAlphaPremultiplication Then srcDIB.SetAlphaPremultiplication False
    Dim srcPixels() As Byte, srcSA As SafeArray1D
    Dim dstPixels() As Byte, dstSA As SafeArray1D
    
    '...and a new, temporary destination image's bytes
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank srcDIB.GetDIBWidth, srcDIB.GetDIBHeight, 32, 0, 0
    
    Dim initY As Long, finalY As Long
    initY = 0
    finalY = m_ButtonHeight - 1
    
    Dim initX As Long, finalX As Long
    initX = 0
    finalX = (m_ButtonWidth - 1) * 4
    
    Dim a As Long
    
    'Create a "hovered" version of the original sprite
    For y = initY To finalY
        srcDIB.WrapArrayAroundScanline srcPixels, srcSA, y
        tmpDIB.WrapArrayAroundScanline dstPixels, dstSA, y
    For x = initX To finalX Step 4
        a = srcPixels(x + 3)
        If (a <> 0) Then
            dstPixels(x) = hLookup(srcPixels(x))
            dstPixels(x + 1) = hLookup(srcPixels(x + 1))
            dstPixels(x + 2) = hLookup(srcPixels(x + 2))
            dstPixels(x + 3) = a
        End If
    Next x
    Next y
    
    srcDIB.UnwrapArrayFromDIB srcPixels
    tmpDIB.UnwrapArrayFromDIB dstPixels
    
    'Premultiply the target DIB, then add it to the central cache
    tmpDIB.SetAlphaPremultiplication True, True
    If thisIsSpecialPressedImage Then
        m_SpriteHandles(st_HoverPressed) = UIImages.AddImage(tmpDIB, origImageName & "-h-p")
    Else
        m_SpriteHandles(st_Hover) = UIImages.AddImage(tmpDIB, origImageName & "-h")
    End If
    
End Sub

Private Sub GenerateVariantButtonImage_Disabled(ByRef srcDIB As pdDIB, ByRef origImageName As String, Optional ByVal thisIsSpecialPressedImage As Boolean = False)
    
    Dim x As Long, y As Long
    
    'We require direct access to the source image's bytes...
    If srcDIB.GetAlphaPremultiplication Then srcDIB.SetAlphaPremultiplication False
    Dim srcPixels() As Byte, srcSA As SafeArray1D
    Dim dstPixels() As Byte, dstSA As SafeArray1D
    
    '...and a new, temporary destination image's bytes
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateBlank srcDIB.GetDIBWidth, srcDIB.GetDIBHeight, 32, 0, 0
    tmpDIB.SetInitialAlphaPremultiplicationState False
    
    Dim initY As Long, finalY As Long
    initY = 0
    finalY = m_ButtonHeight - 1
    
    Dim initX As Long, finalX As Long
    initX = 0
    finalX = (m_ButtonWidth - 1) * 4
    
    Dim a As Long
    
    'Next, create a grayscale "disabled" version of the sprite.
    ' (For this, note that we use a theme-level disabled color.)
    Dim disabledColor As Long
    disabledColor = g_Themer.GetGenericUIColor(UI_ImageDisabled)
    
    Dim dR As Byte, dG As Byte, dB As Byte
    dR = Colors.ExtractRed(disabledColor)
    dG = Colors.ExtractGreen(disabledColor)
    dB = Colors.ExtractBlue(disabledColor)
    
    For y = initY To finalY
        srcDIB.WrapArrayAroundScanline srcPixels, srcSA, y
        tmpDIB.WrapArrayAroundScanline dstPixels, dstSA, y
    For x = initX To finalX Step 4
        a = srcPixels(x + 3)
        If (a <> 0) Then
            dstPixels(x) = dB
            dstPixels(x + 1) = dG
            dstPixels(x + 2) = dR
            dstPixels(x + 3) = a
        End If
    Next x
    Next y
    
    srcDIB.UnwrapArrayFromDIB srcPixels
    tmpDIB.UnwrapArrayFromDIB dstPixels
    
    'As before, premultiply alpha, then add the image to PD's central cache
    tmpDIB.SetAlphaPremultiplication True, True
    If thisIsSpecialPressedImage Then
        m_SpriteHandles(st_DisabledPressed) = UIImages.AddImage(tmpDIB, origImageName & "-d-p")
    Else
        m_SpriteHandles(st_Disabled) = UIImages.AddImage(tmpDIB, origImageName & "-d")
    End If
    
End Sub

'Flash the button for (n) seconds
Public Sub FlashButton(Optional ByVal flashIntervalInMs As Long = 500, Optional ByVal flashLengthInMs As Long = 3000)
    Set m_FlashTimer = New pdTimer
    m_FlashTimer.Interval = flashIntervalInMs
    m_FlashLength = flashLengthInMs
    m_FlashTimeElapsed = 0
    m_FlashTimer.StartTimer
End Sub

'To support high-DPI settings properly, we expose specialized move+size functions
Public Function GetLeft() As Long
    GetLeft = ucSupport.GetControlLeft
End Function

Public Sub SetLeft(ByVal newLeft As Long)
    ucSupport.RequestNewPosition newLeft, , True
End Sub

Public Function GetTop() As Long
    GetTop = ucSupport.GetControlTop
End Function

Public Sub SetTop(ByVal newTop As Long)
    ucSupport.RequestNewPosition , newTop, True
End Sub

Public Function GetWidth() As Long
    GetWidth = ucSupport.GetControlWidth
End Function

Public Sub SetWidth(ByVal newWidth As Long)
    ucSupport.RequestNewSize newWidth, , True
End Sub

Public Function GetHeight() As Long
    GetHeight = ucSupport.GetControlHeight
End Function

Public Sub SetHeight(ByVal newHeight As Long)
    ucSupport.RequestNewSize , newHeight, True
End Sub

Public Sub SetPosition(ByVal newLeft As Long, ByVal newTop As Long)
    ucSupport.RequestNewPosition newLeft, newTop, True
End Sub

Public Sub SetPositionAndSize(ByVal newLeft As Long, ByVal newTop As Long, ByVal newWidth As Long, ByVal newHeight As Long)
    ucSupport.RequestFullMove newLeft, newTop, newWidth, newHeight, True
End Sub

Private Sub m_FlashTimer_Timer()
    
    m_FlashCount = m_FlashCount + 1
    m_FlashTimeElapsed = m_FlashTimeElapsed + m_FlashTimer.Interval
    
    'Only flash for three seconds (by default; the caller can configure this manually)
    If (m_FlashTimeElapsed >= m_FlashLength) Then
        m_FlashTimer.StopTimer
        m_FlashCount = 0
        m_FlashTimeElapsed = 0
        RedrawBackBuffer True, True
    Else
        RedrawBackBuffer True, False
    End If
    
End Sub

'A few key events are also handled
Private Sub ucSupport_KeyDownCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    
    markEventHandled = False
    
    'If space is pressed, and our value is not true, raise a click event.
    If (vkCode = VK_SPACE) Then
        
        markEventHandled = True
        
        If ucSupport.DoIHaveFocus And Me.Enabled Then
        
            'Sticky toggle mode causes the button to toggle between true/false
            If m_StickyToggle Then
            
                Value = (Not Value)
                RedrawBackBuffer
                RaiseEvent Click(Shift)
            
            'Other modes behave identically
            Else
            
                If (Not m_ButtonState) Then
                    Value = True
                    RedrawBackBuffer
                    RaiseEvent Click(Shift)
                    
                    'During auto-toggle mode, immediately reverse the value after the Click() event is raised
                    If m_AutoToggle Then
                        m_ButtonState = False
                        RedrawBackBuffer True, False
                    End If
                    
                End If
            
            End If
            
        End If
        
    End If

End Sub

Private Sub ucSupport_KeyDownSystem(ByVal Shift As ShiftConstants, ByVal whichSysKey As PD_NavigationKey, markEventHandled As Boolean)
    
    'Enter/Esc get reported directly to the system key handler.  Note that we track the return, because TRUE
    ' means the key was successfully forwarded to the relevant handler.  (If FALSE is returned, no control
    ' accepted the keypress, meaning we should forward the event down the line.)
    markEventHandled = NavKey.NotifyNavKeypress(Me, whichSysKey, Shift)
    
End Sub

'If space was pressed, and AutoToggle is active, remove the button state and redraw it
Private Sub ucSupport_KeyUpCustom(ByVal Shift As ShiftConstants, ByVal vkCode As Long, markEventHandled As Boolean)
    If (vkCode = VK_SPACE) Then
        If Me.Enabled And Value And m_AutoToggle Then
            Value = False
            RedrawBackBuffer
        End If
    End If
End Sub

'To improve responsiveness, MouseDown is used instead of Click.
Private Sub ucSupport_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal timeStamp As Long)
    
    If ((Button And pdLeftButton) <> pdLeftButton) Then Exit Sub
    
    If Me.Enabled Then
        
        'Sticky toggle allows the button to operate as a checkbox
        If m_StickyToggle Then
            Value = (Not Value)
        
        'Non-sticky toggle modes will always cause the button to be TRUE on a MouseDown event
        Else
            Value = True
        End If
        
        RedrawBackBuffer True
        RaiseEvent Click(Shift)
        
        'During auto-toggle mode, immediately reverse the value after the Click() event is raised
        If m_AutoToggle Then
            m_ButtonState = False
            RedrawBackBuffer True, False
        End If
        
    End If
        
End Sub

'Enter/leave events trigger cursor changes and hover-state redraws, so they must be tracked
Private Sub ucSupport_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_HAND
    RedrawBackBuffer
End Sub

Private Sub ucSupport_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    ucSupport.RequestCursor IDC_DEFAULT
    RedrawBackBuffer
End Sub

'If toggle mode is active, remove the button's TRUE state and redraw it
Private Sub ucSupport_MouseUpCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal clickEventAlsoFiring As Boolean, ByVal timeStamp As Long)
    If ((Button And pdLeftButton) <> pdLeftButton) Then Exit Sub
    If m_AutoToggle And Value Then Value = False
    RedrawBackBuffer
End Sub

Private Sub ucSupport_GotFocusAPI()
    RaiseEvent GotFocusAPI
    RedrawBackBuffer
End Sub

Private Sub ucSupport_LostFocusAPI()
    RaiseEvent LostFocusAPI
    RedrawBackBuffer
End Sub

Private Sub ucSupport_RepaintRequired(ByVal updateLayoutToo As Boolean)
    If updateLayoutToo Then UpdateControlLayout
    RedrawBackBuffer
End Sub

Private Sub ucSupport_SetCustomTabTarget(ByVal shiftTabWasPressed As Boolean, newTargetHwnd As Long)
    RaiseEvent SetCustomTabTarget(shiftTabWasPressed, newTargetHwnd)
End Sub

Private Sub ucSupport_VisibilityChange(ByVal newVisibility As Boolean)
    If newVisibility Then RedrawBackBuffer
End Sub

'INITIALIZE control
Private Sub UserControl_Initialize()
    
    'Initialize a user control support class
    Set ucSupport = New pdUCSupport
    ucSupport.RegisterControl UserControl.hWnd, True
    ucSupport.RequestExtraFunctionality True, True
    ucSupport.SpecifyRequiredKeys VK_SPACE
    
    'Initialize the sprite handle collection
    ReDim m_SpriteHandles(0 To 5) As Long
    Dim i As Long
    For i = 0 To 5
        m_SpriteHandles(i) = UI_SPRITE_UNDEFINED
    Next i
    
    'Prep the color manager and load default colors
    Set m_Colors = New pdThemeColors
    Dim colorCount As PDTOOLBUTTON_COLOR_LIST: colorCount = [_Count]
    m_Colors.InitializeColorList "PDToolButton", colorCount
    If Not PDMain.IsProgramRunning() Then UpdateColorList
           
End Sub

'Set default properties
Private Sub UserControl_InitProperties()
    AutoToggle = False
    BackColor = vbWhite
    DontHighlightDownState = False
    StickyToggle = False
    UseCustomBackColor = False
    Value = False
End Sub

'At run-time, painting is handled by the support class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    If Not PDMain.IsProgramRunning() Then ucSupport.RequestIDERepaint UserControl.hDC
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)
    With PropBag
        AutoToggle = .ReadProperty("AutoToggle", False)
        m_BackColor = .ReadProperty("BackColor", vbWhite)
        m_DontHighlightDownState = .ReadProperty("DontHighlightDownState", False)
        StickyToggle = .ReadProperty("StickyToggle", False)
        m_UseCustomBackColor = .ReadProperty("UseCustomBackColor", False)
    End With
End Sub

Private Sub UserControl_Resize()
    If (Not PDMain.IsProgramRunning()) Then ucSupport.NotifyIDEResize UserControl.Width, UserControl.Height
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)
    With PropBag
        .WriteProperty "AutoToggle", AutoToggle, False
        .WriteProperty "BackColor", BackColor, vbWhite
        .WriteProperty "DontHighlightDownState", DontHighlightDownState, False
        .WriteProperty "StickyToggle", StickyToggle, False
        .WriteProperty "UseCustomBackColor", UseCustomBackColor, False
    End With
End Sub

'Because this control automatically forces all internal buttons to identical sizes, we have to recalculate a number
' of internal sizing metrics whenever the control size changes.
Private Sub UpdateControlLayout()
    
    'Retrieve DPI-aware control dimensions from the support class
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    'Determine positioning of the button image, if any
    If (m_ButtonWidth <> 0) Then
        btImageCoords.x = (bWidth - m_ButtonWidth) \ 2
        btImageCoords.y = (bHeight - m_ButtonHeight) \ 2
    End If
    
End Sub

'Use this function to completely redraw the back buffer from scratch.  Note that this is computationally
' expensive compared to just flipping the existing buffer to the screen, so only redraw the backbuffer if
' the control state has changed.
Private Sub RedrawBackBuffer(Optional ByVal raiseImmediateDrawEvent As Boolean = False, Optional ByVal testMouseState As Boolean = True)
    
    'Because this control supports so many different behaviors, color decisions are somewhat complicated.  Note that the
    ' control's BackColor property is only relevant under certain conditions (e.g. if the matching UseCustomBackColor
    ' property is set, the button is not pressed, etc).
    Dim btnColorBorder As Long, btnColorFill As Long
    Dim considerActive As Boolean
    considerActive = (m_ButtonState And (Not m_DontHighlightDownState))
    If testMouseState Then considerActive = considerActive Or (m_AutoToggle And ucSupport.IsMouseButtonDown(pdLeftButton))
    
    'If our owner has requested a custom backcolor, it takes precedence (but only if the button is inactive)
    If m_UseCustomBackColor And (Not considerActive) Then
        btnColorFill = m_BackColor
        If ucSupport.IsMouseInside Or ucSupport.DoIHaveFocus Then
            btnColorBorder = m_Colors.RetrieveColor(PDTB_Border, Me.Enabled, False, True)
        Else
            btnColorBorder = btnColorFill
        End If
    Else
        btnColorFill = m_Colors.RetrieveColor(PDTB_ButtonFill, Me.Enabled, considerActive, ucSupport.IsMouseInside Or ucSupport.DoIHaveFocus)
        btnColorBorder = m_Colors.RetrieveColor(PDTB_Border, Me.Enabled, considerActive, ucSupport.IsMouseInside Or ucSupport.DoIHaveFocus)
    End If
    
    Dim useHoverImage As Boolean
    useHoverImage = ucSupport.IsMouseInside Or ucSupport.DoIHaveFocus
    
    'If the button is currently in "flash" mode, ignore all previous color decisions and overwrite them
    ' with an alternating "flashing" background.
    If (m_FlashCount > 0) Then
        useHoverImage = False
        btnColorFill = m_Colors.RetrieveColor(PDTB_ButtonFill, Me.Enabled, ((m_FlashCount And 1) = 0), False)
        btnColorBorder = m_Colors.RetrieveColor(PDTB_Border, Me.Enabled, True, False)
    End If
    
    'Request the back buffer DC, and ask the support module to erase any existing rendering for us.
    Dim bufferDC As Long
    bufferDC = ucSupport.GetBackBufferDC(True, btnColorFill)
    If (bufferDC = 0) Then Exit Sub
    
    Dim bWidth As Long, bHeight As Long
    bWidth = ucSupport.GetBackBufferWidth
    bHeight = ucSupport.GetBackBufferHeight
    
    If PDMain.IsProgramRunning() Then
        
        'A single-pixel border is always drawn around the control
        Dim borderSize As Single
        If ucSupport.DoIHaveFocus Then borderSize = 3! Else borderSize = 1!
        
        Dim cSurface As pd2DSurface: Set cSurface = New pd2DSurface
        cSurface.WrapSurfaceAroundDC bufferDC
        cSurface.SetSurfaceAntialiasing P2_AA_None
        
        Dim cPen As New pd2DPen: Set cPen = New pd2DPen
        cPen.SetPenColor btnColorBorder
        cPen.SetPenWidth borderSize
        cPen.SetPenLineJoin P2_LJ_Miter
        
        PD2D.DrawRectangleI_AbsoluteCoords cSurface, cPen, 0, 0, bWidth - 1, bHeight - 1
        Set cSurface = Nothing
        
        'Paint the image, if any
        If (m_ButtonWidth <> 0) Then
            
            Dim targetSpriteHandle As Long, tmpDIB As pdDIB, tmpDIBName As String
            targetSpriteHandle = -1
            
            If Me.Enabled Then
                If (Me.Value And m_ButtonImagesPressed) Then
                    If useHoverImage Then
                        targetSpriteHandle = m_SpriteHandles(st_HoverPressed)
                    Else
                        targetSpriteHandle = m_SpriteHandles(st_NormalPressed)
                    End If
                Else
                    If useHoverImage Then
                        targetSpriteHandle = m_SpriteHandles(st_Hover)
                    Else
                        targetSpriteHandle = m_SpriteHandles(st_Normal)
                    End If
                End If
            Else
                If (Me.Value And m_ButtonImagesPressed) Then
                    targetSpriteHandle = m_SpriteHandles(st_DisabledPressed)
                Else
                    targetSpriteHandle = m_SpriteHandles(st_Disabled)
                End If
            End If
            
            'If the requested sprite doesn't exist, this may be the first time we've attempted
            ' to paint it (e.g. a "disabled" or "hovered" copy of the original DIB may be needed).
            ' Such images are created on-the-fly, so check for such a state, then create the
            ' necessary DIB if needed.
            If (targetSpriteHandle < 0) Then
                
                If Me.Enabled Then
                    If (Me.Value And m_ButtonImagesPressed) Then
                        If useHoverImage Then
                            Set tmpDIB = UIImages.GetCopyOfSprite(m_SpriteHandles(st_NormalPressed), tmpDIBName)
                            If (Not tmpDIB Is Nothing) Then GenerateVariantButtonImage_Hover tmpDIB, tmpDIBName, True
                            targetSpriteHandle = m_SpriteHandles(st_HoverPressed)
                        End If
                    Else
                        If useHoverImage Then
                            Set tmpDIB = UIImages.GetCopyOfSprite(m_SpriteHandles(st_Normal), tmpDIBName)
                            If (Not tmpDIB Is Nothing) Then GenerateVariantButtonImage_Hover tmpDIB, tmpDIBName, False
                            targetSpriteHandle = m_SpriteHandles(st_Hover)
                        End If
                    End If
                Else
                    If (Me.Value And m_ButtonImagesPressed) Then
                        Set tmpDIB = UIImages.GetCopyOfSprite(m_SpriteHandles(st_NormalPressed), tmpDIBName)
                        If (Not tmpDIB Is Nothing) Then GenerateVariantButtonImage_Disabled tmpDIB, tmpDIBName, True
                        targetSpriteHandle = m_SpriteHandles(st_DisabledPressed)
                    Else
                        Set tmpDIB = UIImages.GetCopyOfSprite(m_SpriteHandles(st_Normal), tmpDIBName)
                        If (Not tmpDIB Is Nothing) Then GenerateVariantButtonImage_Disabled tmpDIB, tmpDIBName, False
                        targetSpriteHandle = m_SpriteHandles(st_Disabled)
                    End If
                End If
            
            End If
            
            'We have now performed an exhaustive search for this button's image.  Paint it if found.
            If (targetSpriteHandle >= 0) Then
                UIImages.PaintCachedImage bufferDC, btImageCoords.x, btImageCoords.y, targetSpriteHandle
                UIImages.SuspendSprite targetSpriteHandle
            End If
            
        End If
        
    End If
    
    'Paint the final result to the screen, as relevant
    ucSupport.RequestRepaint raiseImmediateDrawEvent
    
End Sub

'Before this control does any painting, we need to retrieve relevant colors from PD's primary theming class.  Note that this
' step must also be called if/when PD's visual theme settings change.
Private Sub UpdateColorList()
    With m_Colors
        .LoadThemeColor PDTB_Background, "Background", IDE_WHITE
        .LoadThemeColor PDTB_ButtonFill, "ButtonFill", IDE_WHITE
        .LoadThemeColor PDTB_Border, "Border", IDE_WHITE
    End With
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub UpdateAgainstCurrentTheme(Optional ByVal hostFormhWnd As Long = 0)
    If ucSupport.ThemeUpdateRequired Then
        UpdateColorList
        If PDMain.IsProgramRunning() Then NavKey.NotifyControlLoad Me, hostFormhWnd
        If PDMain.IsProgramRunning() Then ucSupport.UpdateAgainstThemeAndLanguage
    End If
End Sub

'By design, PD prefers to not use design-time tooltips.  Apply tooltips at run-time, using this function.
' (IMPORTANT NOTE: translations are handled automatically.  Always pass the original English text!)
Public Sub AssignTooltip(ByRef newTooltip As String, Optional ByRef newTooltipTitle As String = vbNullString, Optional ByVal raiseTipsImmediately As Boolean = False)
    ucSupport.AssignTooltip UserControl.ContainerHwnd, newTooltip, newTooltipTitle, raiseTipsImmediately
End Sub
