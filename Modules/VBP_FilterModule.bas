Attribute VB_Name = "Filters_Area"
'***************************************************************************
'Filter (Area) Interface
'Copyright �2000-2012 by Tanner Helland
'Created: 12/June/01
'Last updated: 28/August/12
'Last update: fixed potential out-of-range error on Grid Blur
'Still needs: -removal of goto numbers (text labels are preferable)
'             -interpolation for isometric conversion
'
'Holder for generalized area filters.  Also contains the DoFilter routine, which is central to running
' custom filters (as well as some of the intrinsic PhotoDemon ones).
'
'***************************************************************************

Option Explicit

'These constants are related to saving/loading custom filters to/from a file
Public Const CUSTOM_FILTER_ID As String * 4 = "DScf"
Public Const CUSTOM_FILTER_VERSION_2003 = &H80000000
Public Const CUSTOM_FILTER_VERSION_2012 = &H80000001

'The omnipotent DoFilter routine - it takes whatever is in FM() - the "filter matrix" and applies it to the image
Public Sub DoFilter(Optional ByVal FilterType As String = "custom", Optional ByVal InvertResult As Boolean = False, Optional ByVal srcFilterFile As String = "", Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As PictureBox)
    
    'If requested, load the custom filter data from a file
    If srcFilterFile <> "" Then
        Message "Loading custom filter information..."
        Dim FilterReturn As Boolean
        FilterReturn = LoadCustomFilterData(srcFilterFile)
        If FilterReturn = False Then
            Err.Raise 1024, PROGRAMNAME, "Invalid custom filter file"
            Exit Sub
        End If
    End If
    
    'Note that the only purpose of the FilterType string is to display this message
    If toPreview = False Then
        Message "Applying " & FilterType & " filter..."
    End If
    
    'Create a local array and point it at the pixel data we want to operate on
    Dim ImageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    prepImageData tmpSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(ImageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, x2 As Long, y2 As Long
    Dim initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curLayerValues.Left
    initY = curLayerValues.Top
    finalX = curLayerValues.Right
    finalY = curLayerValues.Bottom
    
    Dim checkXMin As Long, checkXMax As Long, checkYMin As Long, checkYMax As Long
    checkXMin = curLayerValues.MinX
    checkXMax = curLayerValues.MaxX
    checkYMin = curLayerValues.MinY
    checkYMax = curLayerValues.MaxY
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim QuickVal As Long, qvDepth As Long
    qvDepth = curLayerValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = findBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    
    'CalcVar determines the size of each sub-loop (so that we don't waste time running a 5x5 matrix on 3x3 filters)
    Dim CalcVar As Long
    CalcVar = (FilterSize \ 2)
        
    'iFM() will hold the contents of FM() - the filter matrix; we don't use FM directly in case other events want to access it
    Dim iFM() As Long
    
    'Resize iFM according to the size of the filter matrix, then copy over the contents of FM()
    If FilterSize = 3 Then ReDim iFM(-1 To 1, -1 To 1) As Long Else ReDim iFM(-2 To 2, -2 To 2) As Long
    iFM = FM
    
    'FilterWeightA and FilterBiasA are copies of the global FilterWeight and FilterBias variables; again, we don't use the originals in case other events
    ' want to access them
    Dim FilterWeightA As Long, FilterBiasA As Long
    FilterWeightA = FilterWeight
    FilterBiasA = FilterBias
    
    'FilterWeightTemp will be reset for every pixel, and decremented appropriately when attempting to calculate the value for pixels
    ' outside the image perimeter
    Dim FilterWeightTemp As Long
    
    'Temporary calculation variables
    Dim CalcX As Long, CalcY As Long
    
    'Create a temporary layer and resize it to the same size as the current image
    Dim tmpLayer As pdLayer
    Set tmpLayer = New pdLayer
    tmpLayer.createFromExistingLayer pdImages(CurrentImage).mainLayer
    
    'Create a local array and point it at the pixel data of our temporary layer.  This will be used to access the current pixel data
    ' without modifications, while the actual image data will be modified by the filter as it's processed.
    Dim tmpData() As Byte
    Dim tSA As SAFEARRAY2D
    prepSafeArray tSA, tmpLayer
    CopyMemory ByVal VarPtrArray(tmpData()), VarPtr(tSA), 4
    
    'QuickValInner is like QuickVal below, but for sub-loops
    Dim QuickValInner As Long
        
    'Apply the filter
    For x = initX To finalX
        QuickVal = x * qvDepth
    For y = initY To finalY
        
        'Reset our values upon beginning analysis on a new pixel
        r = 0
        g = 0
        b = 0
        FilterWeightTemp = FilterWeightA
        
        'Run a sub-loop around the current pixel
        For x2 = x - CalcVar To x + CalcVar
            QuickValInner = x2 * 3
        For y2 = y - CalcVar To y + CalcVar
        
            CalcX = x2 - x
            CalcY = y2 - y
            
            'If no filter value is being applied to this pixel, ignore it (GoTo's aren't generally a part of good programming,
            ' but because VB does not provide a "continue next" type mechanism, GoTo's are all we've got.)
            If iFM(CalcX, CalcY) = 0 Then GoTo NextCustomFilterPixel
            
            'If this pixel lies outside the image perimeter, ignore it and adjust FilterWeight accordingly
            If x2 < checkXMin Or y2 < checkYMin Or x2 > checkXMax Or y2 > checkYMax Then
                FilterWeightTemp = FilterWeightTemp - iFM(CalcX, CalcY)
                GoTo NextCustomFilterPixel
            End If
            
            'Adjust red, green, and blue according to the values in the filter matrix (FM)
            r = r + (tmpData(QuickValInner + 2, y2) * iFM(CalcX, CalcY))
            g = g + (tmpData(QuickValInner + 1, y2) * iFM(CalcX, CalcY))
            b = b + (tmpData(QuickValInner, y2) * iFM(CalcX, CalcY))

NextCustomFilterPixel:  Next y2
        Next x2
        
        'If a weight has been set, apply it now
        If (FilterWeightA <> 1) And (FilterWeightTemp <> 0) Then
            r = r \ FilterWeightTemp
            g = g \ FilterWeightTemp
            b = b \ FilterWeightTemp
        End If
        
        'If a bias has been specified, apply it now
        If FilterBiasA <> 0 Then
            r = r + FilterBiasA
            g = g + FilterBiasA
            b = b + FilterBiasA
        End If
        
        'Make sure all values are between 0 and 255
        If r < 0 Then
            r = 0
        ElseIf r > 255 Then
            r = 255
        End If
        
        If g < 0 Then
            g = 0
        ElseIf g > 255 Then
            g = 255
        End If
        
        If b < 0 Then
            b = 0
        ElseIf b > 255 Then
            b = 255
        End If
        
        'If inversion is specified, apply it now
        If InvertResult = True Then
            r = 255 - r
            g = 255 - g
            b = 255 - b
        End If
        
        'Finally, remember the new value in our tData array
        ImageData(QuickVal + 2, y) = r
        ImageData(QuickVal + 1, y) = g
        ImageData(QuickVal, y) = b
        
    Next y
        If toPreview = False Then
            If (x And progBarCheck) = 0 Then SetProgBarVal x
        End If
    Next x
    
    'With our work complete, point ImageData() and tmpData() away from their respective DIBs and deallocate them
    CopyMemory ByVal VarPtrArray(ImageData), 0&, 4
    Erase ImageData
    
    CopyMemory ByVal VarPtrArray(tmpData), 0&, 4
    Erase tmpData
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    finalizeImageData toPreview, dstPic
    
End Sub

'This subroutine will load the data from a custom filter file straight into the FM() array
Public Function LoadCustomFilterData(ByRef FilterPath As String) As Boolean
    
    'These are used to load values from the filter file; previously, they were integers, but in
    ' 2012 I changed them to Longs.  PhotoDemon loads both types.
    Dim tmpVal As Integer
    Dim tmpValLong As Long
    
    'Open the specified path
    Dim fileNum As Integer
    fileNum = FreeFile
    
    Open FilterPath For Binary As #fileNum
        
        'Verify that the filter is actually a valid filter file
        Dim VerifyID As String * 4
        Get #fileNum, 1, VerifyID
        If (VerifyID <> CUSTOM_FILTER_ID) Then
            Close #fileNum
            LoadCustomFilterData = False
            Exit Function
        End If
        'End verification
       
        'Next get the version number (gotta have this for backwards compatibility)
        Dim VersionNumber As Long
        Get #fileNum, , VersionNumber
        If (VersionNumber <> CUSTOM_FILTER_VERSION_2003) And (VersionNumber <> CUSTOM_FILTER_VERSION_2012) Then
            Message "Unsupported custom filter version."
            Close #fileNum
            LoadCustomFilterData = False
        End If
        'End version check
        
        If VersionNumber = CUSTOM_FILTER_VERSION_2003 Then
            Get #fileNum, , tmpVal
            FilterWeight = tmpVal
            Get #fileNum, , tmpVal
            FilterBias = tmpVal
        ElseIf VersionNumber = CUSTOM_FILTER_VERSION_2012 Then
            Get #fileNum, , tmpValLong
            FilterWeight = tmpValLong
            Get #fileNum, , tmpValLong
            FilterBias = tmpValLong
        End If
        
        'Resize the filter array to fit the default filter size
        FilterSize = 5
        ReDim FM(-2 To 2, -2 To 2) As Long
        'Dim a temporary array from which to load the array data
        Dim tFilterArray(0 To 24) As Long
        
        If VersionNumber = CUSTOM_FILTER_VERSION_2003 Then
            For x = 0 To 24
                Get #fileNum, , tmpVal
                tFilterArray(x) = tmpVal
            Next x
        ElseIf VersionNumber = CUSTOM_FILTER_VERSION_2012 Then
            For x = 0 To 24
                Get #fileNum, , tmpValLong
                tFilterArray(x) = tmpValLong
            Next x
        End If
        
        'Now dump the temporary array into the filter array
        For x = -2 To 2
        For y = -2 To 2
            FM(x, y) = tFilterArray((x + 2) + (y + 2) * 5)
        Next y
        Next x
    'Close the file up
    Close #fileNum
    LoadCustomFilterData = True
End Function

'A very, very gentle softening effect
Public Sub FilterAntialias()
    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    FM(-1, 0) = 1
    FM(1, 0) = 1
    FM(0, -1) = 1
    FM(0, 1) = 1
    FM(0, 0) = 6
    FilterWeight = 10
    FilterBias = 0
    DoFilter "Antialias"
End Sub

'"Soften an image" (aka, apply a gentle 3x3 blur)
Public Sub FilterSoften()
    
    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = 1
    FM(-1, 0) = 1
    FM(-1, 1) = 1
    
    FM(0, -1) = 1
    FM(0, 0) = 8
    FM(0, 1) = 1
    
    FM(1, -1) = 1
    FM(1, 0) = 1
    FM(1, 1) = 1
    
    FilterWeight = 16
    FilterBias = 0
    
    DoFilter "Soften"
    
End Sub

'"Soften an image more" (aka, apply a gentle 5x5 blur)
Public Sub FilterSoftenMore()
    
    FilterSize = 5
    ReDim FM(-2 To 2, -2 To 2) As Long
    
    FM(-2, -2) = 1
    FM(-2, -1) = 1
    FM(-2, 0) = 1
    FM(-2, 1) = 1
    FM(-2, 2) = 1
    
    FM(-1, -2) = 1
    FM(-1, -1) = 1
    FM(-1, 0) = 1
    FM(-1, 1) = 1
    FM(-1, 2) = 1
    
    FM(0, -2) = 1
    FM(0, -1) = 1
    FM(0, 0) = 24
    FM(0, 1) = 1
    FM(0, 2) = 1
    
    FM(1, -2) = 1
    FM(1, -1) = 1
    FM(1, 0) = 1
    FM(1, 1) = 1
    FM(1, 2) = 1
    
    FM(2, -2) = 1
    FM(2, -1) = 1
    FM(2, 0) = 1
    FM(2, 1) = 1
    FM(2, 2) = 1
    
    FilterWeight = 48
    FilterBias = 0
    
    DoFilter "Strong Soften"
    
End Sub

'Blur an image using a 3x3 convolution matrix
Public Sub FilterBlur()
        
    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = 1
    FM(-1, 0) = 1
    FM(-1, 1) = 1
    
    FM(0, -1) = 1
    FM(0, 0) = 1
    FM(0, 1) = 1
    
    FM(1, -1) = 1
    FM(1, 0) = 1
    FM(1, 1) = 1
    
    FilterWeight = 9
    FilterBias = 0
    
    DoFilter "Blur"
    
End Sub

'Blur an image using a 5x5 convolution matrix
Public Sub FilterBlurMore()
    
    FilterSize = 5
    ReDim FM(-2 To 2, -2 To 2) As Long
    
    FM(-2, -2) = 1
    FM(-2, -1) = 1
    FM(-2, 0) = 1
    FM(-2, 1) = 1
    FM(-2, 2) = 1
    
    FM(-1, -2) = 1
    FM(-1, -1) = 1
    FM(-1, 0) = 1
    FM(-1, 1) = 1
    FM(-1, 2) = 1
    
    FM(0, -2) = 1
    FM(0, -1) = 1
    FM(0, 0) = 1
    FM(0, 1) = 1
    FM(0, 2) = 1
    
    FM(1, -2) = 1
    FM(1, -1) = 1
    FM(1, 0) = 1
    FM(1, 1) = 1
    FM(1, 2) = 1
    
    FM(2, -2) = 1
    FM(2, -1) = 1
    FM(2, 0) = 1
    FM(2, 1) = 1
    FM(2, 2) = 1
    
    FilterWeight = 25
    FilterBias = 0
    
    DoFilter "Strong Blur"
    
End Sub

'3x3 Gaussian blur
Public Sub FilterGaussianBlur()

    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = 1
    FM(0, -1) = 2
    FM(1, -1) = 1
    
    FM(-1, 0) = 2
    FM(0, 0) = 4
    FM(1, 0) = 2
    
    FM(-1, 1) = 1
    FM(0, 1) = 2
    FM(1, 1) = 1
    
    FilterWeight = 16
    FilterBias = 0
    
    DoFilter "Gaussian Blur"
    
End Sub

'5x5 Gaussian blur
Public Sub FilterGaussianBlurMore()

    FilterSize = 5
    ReDim FM(-2 To 2, -2 To 2) As Long
    
    FM(-2, -2) = 1
    FM(-1, -2) = 4
    FM(0, -2) = 7
    FM(1, -2) = 4
    FM(2, -2) = 1
    
    FM(-2, -1) = 4
    FM(-1, -1) = 16
    FM(0, -1) = 26
    FM(1, -1) = 16
    FM(2, -1) = 4
    
    FM(-2, 0) = 7
    FM(-1, 0) = 26
    FM(0, 0) = 41
    FM(1, 0) = 26
    FM(2, 0) = 7
    
    FM(-2, 1) = 4
    FM(-1, 1) = 16
    FM(0, 1) = 26
    FM(1, 1) = 16
    FM(2, 1) = 4
    
    FM(-2, 2) = 1
    FM(-1, 2) = 4
    FM(0, 2) = 7
    FM(1, 2) = 4
    FM(2, 2) = 1
    
    FilterWeight = 273
    FilterBias = 0
    
    DoFilter "Strong Gaussian Blur"
    
End Sub

'Sharpen an image via convolution filter
Public Sub FilterSharpen()
    
    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = -1
    FM(0, -1) = -1
    FM(1, -1) = -1
    
    FM(-1, 0) = -1
    FM(0, 0) = 15
    FM(1, 0) = -1
    
    FM(-1, 1) = -1
    FM(0, 1) = -1
    FM(1, 1) = -1
    
    FilterWeight = 7
    FilterBias = 0
    
    DoFilter "Sharpen"
  
End Sub

'Strongly sharpen an image via convolution filter
Public Sub FilterSharpenMore()

    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = 0
    FM(0, -1) = -1
    FM(1, -1) = 0
    
    FM(-1, 0) = -1
    FM(0, 0) = 5
    FM(1, 0) = -1
    
    FM(-1, 1) = 0
    FM(0, 1) = -1
    FM(1, 1) = 0
    
    FilterWeight = 1
    FilterBias = 0
    
    DoFilter "Strong Sharpen"
  
End Sub

'"Unsharp" an image - it's a stupid name, but that's the industry standard.  Basically, blur the image, then subtract that from the original image.
Public Sub FilterUnsharp()

    FilterSize = 3
    ReDim FM(-1 To 1, -1 To 1) As Long
    
    FM(-1, -1) = -1
    FM(0, -1) = -2
    FM(1, -1) = -1
    
    FM(-1, 0) = -2
    FM(0, 0) = 24
    FM(1, 0) = -2
    
    FM(-1, 1) = -1
    FM(0, 1) = -2
    FM(1, 1) = -1
    
    FilterWeight = 12
    FilterBias = 0
    
    DoFilter "Unsharp"
  
  End Sub

'Apply a grid blur to an image; basically, blur every vertical line, then every horizontal line, then average the results
Public Sub FilterGridBlur()

    Message "Generating grids..."

    'Create a local array and point it at the pixel data we want to operate on
    Dim ImageData() As Byte
    Dim tmpSA As SAFEARRAY2D
    prepImageData tmpSA
    CopyMemory ByVal VarPtrArray(ImageData()), VarPtr(tmpSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = curLayerValues.Left
    initY = curLayerValues.Top
    finalX = curLayerValues.Right
    finalY = curLayerValues.Bottom
    
    Dim iWidth As Long, iHeight As Long
    iWidth = curLayerValues.Width
    iHeight = curLayerValues.Height
            
    Dim numOfPixels As Long
    numOfPixels = iWidth + iHeight
            
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim QuickVal As Long, qvDepth As Long
    qvDepth = curLayerValues.BytesPerPixel
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    progBarCheck = findBestProgBarValue()
    
    'Finally, a bunch of variables used in color calculation
    Dim r As Long, g As Long, b As Long
    Dim h As Single, s As Single, l As Single
    Dim rax() As Long, gax() As Long, bax() As Long
    Dim ray() As Long, gay() As Long, bay() As Long
    ReDim rax(0 To iWidth) As Long, gax(0 To iWidth) As Long, bax(0 To iWidth) As Long
    ReDim ray(0 To iHeight) As Long, gay(0 To iHeight), bay(0 To iHeight)
    
    'Generate the averages for vertical lines
    For x = initX To finalX
        r = 0
        g = 0
        b = 0
        QuickVal = x * 3
        For y = initY To finalY
            r = r + ImageData(QuickVal + 2, y)
            g = g + ImageData(QuickVal + 1, y)
            b = b + ImageData(QuickVal, y)
        Next y
        rax(x) = r
        gax(x) = g
        bax(x) = b
    Next x
    
    'Generate the averages for horizontal lines
    For y = initY To finalY
        r = 0
        g = 0
        b = 0
        For x = initX To finalX
            QuickVal = x * 3
            r = r + ImageData(QuickVal + 2, y)
            g = g + ImageData(QuickVal + 1, y)
            b = b + ImageData(QuickVal, y)
        Next x
        ray(y) = r
        gay(y) = g
        bay(y) = b
    Next y
    
    Message "Applying grid blur..."
        
    'Apply the filter
    For x = initX To finalX
        QuickVal = x * qvDepth
    For y = initY To finalY
        
        'Average the horizontal and vertical values for each color component
        r = (rax(x) + ray(y)) \ numOfPixels
        g = (gax(x) + gay(y)) \ numOfPixels
        b = (bax(x) + bay(y)) \ numOfPixels
        
        'The colors shouldn't exceed 255, but it doesn't hurt to double-check
        If r > 255 Then r = 255
        If g > 255 Then g = 255
        If b > 255 Then b = 255
        
        'Assign the new RGB values back into the array
        ImageData(QuickVal + 2, y) = r
        ImageData(QuickVal + 1, y) = g
        ImageData(QuickVal, y) = b
        
    Next y
        If (x And progBarCheck) = 0 Then SetProgBarVal x
    Next x
        
    'With our work complete, point ImageData() away from the DIB and deallocate it
    CopyMemory ByVal VarPtrArray(ImageData), 0&, 4
    Erase ImageData
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering
    finalizeImageData

End Sub

Public Sub FilterIsometric()
    Message "Preparing conversion tables..."
    
    'Get the current image data and prepare all the picture boxes
    GetImageData True
    Dim hWidth As Long
    Dim oWidth As Long, oHeight As Long
    oWidth = PicWidthL
    oHeight = PicHeightL
    hWidth = (PicWidthL \ 2)
    
    PicWidthL = PicHeightL + PicWidthL + 1
    PicHeightL = PicWidthL \ 2
    
    FormMain.ActiveForm.BackBuffer.AutoSize = False
    FormMain.ActiveForm.BackBuffer.Width = PicWidthL + 3
    FormMain.ActiveForm.BackBuffer.Height = PicHeightL + 3
    FormMain.ActiveForm.BackBuffer.Picture = LoadPicture("")
    FormMain.ActiveForm.BackBuffer2.Width = FormMain.ActiveForm.BackBuffer.Width
    FormMain.ActiveForm.BackBuffer2.Height = FormMain.ActiveForm.BackBuffer.Height
    FormMain.ActiveForm.BackBuffer2.Picture = FormMain.ActiveForm.BackBuffer.Picture
    
    DoEvents
    
    GetImageData2 True
    
    'Display the new size
    DisplaySize PicWidthL + 1, PicHeightL + 1
    
    'Perform the translation
    Message "Generating isometric image..."
    SetProgBarMax PicWidthL
    
    Dim TX As Long, TY As Long, QuickVal As Long, QuickVal2 As Long
    
    For x = 0 To PicWidthL
    For y = 0 To PicHeightL
        
        QuickVal2 = x * 3
        TX = getIsometricX(x, y, hWidth)
        
        QuickVal = TX * 3
        TY = getIsometricY(x, y, hWidth)
        
        If (TX >= 0 And TX <= oWidth And TY >= 0 And TY <= oHeight) Then
            ImageData2(QuickVal2 + 2, y) = ImageData(QuickVal + 2, TY)
            ImageData2(QuickVal2 + 1, y) = ImageData(QuickVal + 1, TY)
            ImageData2(QuickVal2, y) = ImageData(QuickVal, TY)
        Else
            ImageData2(QuickVal2 + 2, y) = 255
            ImageData2(QuickVal2 + 1, y) = 255
            ImageData2(QuickVal2, y) = 255
        End If
    
    Next y
        If x Mod 20 = 0 Then SetProgBarVal x
    Next x
    
    SetProgBarVal cProgBar.Max
    
    SetImageData2 True
    
    FormMain.ActiveForm.BackBuffer.Picture = FormMain.ActiveForm.BackBuffer2.Picture
    FormMain.ActiveForm.BackBuffer2.Picture = LoadPicture("")
    FormMain.ActiveForm.BackBuffer2.Width = 1
    FormMain.ActiveForm.BackBuffer2.Height = 1
    
    SetProgBarVal 0
    
    FitOnScreen
End Sub

'These two functions translate a normal (x,y) coordinate to an isometric plane
Private Function getIsometricX(ByVal xc As Long, ByVal yc As Long, ByVal tWidth As Long) As Long
    getIsometricX = (xc / 2) - yc + tWidth
End Function

Private Function getIsometricY(ByVal xc As Long, ByVal yc As Long, ByVal tWidth As Long) As Long
    getIsometricY = (xc / 2) + yc - tWidth
End Function

'Temporary arrays are necessary for many area transformations - this handles the transfer between the temp array and ImageData()
Public Sub TransferImageData()
    Message "Transferring data..."
    Dim QuickVal As Long
    For x = 0 To PicWidthL
        QuickVal = x * 3
    For y = 0 To PicHeightL
        ImageData(QuickVal + 2, y) = tData(QuickVal + 2, y)
        ImageData(QuickVal + 1, y) = tData(QuickVal + 1, y)
        ImageData(QuickVal, y) = tData(QuickVal, y)
    Next y
    Next x
    
    Erase tData
    
End Sub
