VERSION 5.00
Begin VB.Form FormSurfaceBlur 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Surface blur"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12090
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   806
   ShowInTaskbar   =   0   'False
   Begin PhotoDemon.pdCommandBar cmdBar 
      Align           =   2  'Align Bottom
      Height          =   750
      Left            =   0
      TabIndex        =   0
      Top             =   5790
      Width           =   12090
      _ExtentX        =   21325
      _ExtentY        =   1323
   End
   Begin PhotoDemon.pdSlider sldRadius 
      Height          =   705
      Left            =   6000
      TabIndex        =   2
      Top             =   1920
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "radius"
      Min             =   1
      Max             =   500
      SigDigits       =   1
      ScaleStyle      =   1
      Value           =   3
      DefaultValue    =   3
   End
   Begin PhotoDemon.pdFxPreviewCtl pdFxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.pdSlider sldRange 
      Height          =   705
      Left            =   6000
      TabIndex        =   3
      Top             =   2880
      Width           =   5895
      _ExtentX        =   10398
      _ExtentY        =   1270
      Caption         =   "threshold"
      Min             =   1
      Max             =   100
      SigDigits       =   1
      ScaleStyle      =   1
      Value           =   20
      NotchPosition   =   2
      NotchValueCustom=   20
   End
End
Attribute VB_Name = "FormSurfaceBlur"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Surface Blur (bilateral filter)
'Copyright 2014-2020 by Tanner Helland
'Created: 19/June/14
'Last updated: 04/December/19
'Last update: fully convert to recursive bilateral implementation
'
'Per Wikipedia (https://en.wikipedia.org/wiki/Bilateral_filter):
' "A bilateral filter is a non-linear, edge-preserving, and noise-reducing smoothing filter for images.
' It replaces the intensity of each pixel with a weighted average of intensity values from nearby pixels.
' This weight can be based on a Gaussian distribution. Crucially, the weights depend not only on
' Euclidean distance of pixels, but also on the radiometric differences (e.g., range differences, such as
' color intensity, depth distance, etc.). This preserves sharp edges."
'
'More details on bilateral filtering can be found at:
' http://www.cs.duke.edu/~tomasi/papers/tomasi/tomasiIccv98.pdf
'
'Because traditional 2D kernel convolution is extremely slow on images of any size, PhotoDemon used
' a separable bilateral filter implementation for many years.  This provided a good approximation of
' a true bilateral, and it transformed the filter from an O(w*h*r^2) process to O(w*h*2r).
'
'For details on a separable bilateral approach, see:
' http://homepage.tudelft.nl/e3q6n/publications/2005/ICME2005_TPLV.pdf
'
'In 2019, I bit the bullet and translated a (lengthy, complicated) recursive bilateral filter
' implementation into VB6.  This is the current state-of-the-art for real-time bilateral filtering.
' It was developed by Qingxiong Yang and first published in an influential 2012 paper:
' https://link.springer.com/content/pdf/10.1007%2F978-3-642-33718-5_29.pdf
'
'This technique reduces the filter to a constant-time filter of just O(w*h).
'
'PD's implementation is based on a 2017 C++ implementation of Yang's work by Ming:
'
'https://github.com/ufoym/recursive-bf
'
'Ming's code is available under an MIT license.  Thank you to him/her/them for sharing their work!
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit https://photodemon.org/license/
'
'***************************************************************************

Option Explicit

Private WithEvents m_Bilateral As pdFxBilateral
Attribute m_Bilateral.VB_VarHelpID = -1

Public Sub BilaterFilter_Master(ByVal effectParams As String, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As pdFxPreviewCtl)
    
    If (Not toPreview) Then Message "Applying surface blur..."
    
    Dim cParams As pdSerialize
    Set cParams = New pdSerialize
    cParams.SetParamString effectParams
    
    Dim kernelRadius As Long, rangeFactor As Double
    
    With cParams
        kernelRadius = .GetLong("radius", 1)
        rangeFactor = .GetDouble("range", 10#)
    End With
    
    'PrepImageData generates a working copy of the current filter target
    Dim dstSA As SafeArray2D
    EffectPrep.PrepImageData dstSA, toPreview, dstPic, , , True
    
    'If this is a preview, we need to adjust kernel size to match
    If toPreview Then kernelRadius = kernelRadius * curDIBValues.previewModifier
    
    'Enforce a minimum radius of 1; below this, the recursive filter may experience OOB errors
    If (kernelRadius < 1#) Then kernelRadius = 1#
    
    'As of 2019, PD supports an ultra-fast recursive bilateral filter (adapted from this
    ' MIT-licensed code: https://github.com/ufoym/recursive-bf).  This is now used
    ' exclusively by the program, although the old (separable) implementation still exists
    ' in case we need it in the future... note, however, that the separable implementation
    ' supports additional inputs, which are no longer provided via the UI.
    Dim useRecursiveBF As Boolean
    useRecursiveBF = True
    
    If useRecursiveBF Then
        
        'For non-previews, set up the progress bar.  (Note that we have to use an integer value,
        ' or taskbar progress updates won't work - this is specifically an OS limitation, as PD's
        ' internal progress bar works just fine with [0, 1] progress values.)
        If (Not toPreview) Then ProgressBars.SetProgBarMax 100#
        
        If (m_Bilateral Is Nothing) Then Set m_Bilateral = New pdFxBilateral
        m_Bilateral.Bilateral_Recursive workingDIB, kernelRadius, rangeFactor, (Not toPreview)
        
        'The returned result is not guaranteed to be perfectly premultiplied, as the bilateral
        ' function can change colors in unpredictable ways.  Forcibly unpremultiply it just to
        ' be safe.  (The effect handler will take care of re-premultiplying it for us.)
        workingDIB.SetAlphaPremultiplication False, True
        
    Else
        'Filters_Layers.CreateBilateralDIB workingDIB, kernelRadius, spatialFactor, colorFactor, toPreview
    End If
        
    'Finalize result
    EffectPrep.FinalizeImageData toPreview, dstPic
    
End Sub

Private Sub cmdBar_OKClick()
    Process "Bilateral smoothing", , GetLocalParamString(), UNDO_Layer
End Sub

Private Sub cmdBar_RequestPreviewUpdate()
    UpdatePreview
End Sub

Private Sub Form_Load()
    cmdBar.SetPreviewStatus False
    ApplyThemeAndTranslations Me
    cmdBar.SetPreviewStatus True
    UpdatePreview
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub m_Bilateral_ProgressUpdate(ByVal progressValue As Single, cancelOperation As Boolean)
    ProgressBars.SetProgBarVal progressValue * 100!
End Sub

Private Sub sldRadius_Change()
    UpdatePreview
End Sub

Private Sub sldRange_Change()
    UpdatePreview
End Sub

Private Sub UpdatePreview()
    If cmdBar.PreviewsAllowed Then BilaterFilter_Master GetLocalParamString(), True, pdFxPreview
End Sub

'If the user changes the position and/or zoom of the preview viewport, the entire preview must be redrawn.
Private Sub pdFxPreview_ViewportChanged()
    UpdatePreview
End Sub

Private Function GetLocalParamString() As String
    
    Dim cParams As pdSerialize
    Set cParams = New pdSerialize
    
    With cParams
        .AddParam "radius", sldRadius.Value
        .AddParam "range", sldRange.Value
    End With
    
    GetLocalParamString = cParams.GetParamString()
    
End Function
