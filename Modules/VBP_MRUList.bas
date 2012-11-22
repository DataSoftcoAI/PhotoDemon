Attribute VB_Name = "MRU_List_Handler"
'***************************************************************************
'MRU (Most Recently Used) List Handler
'Copyright �2005-2012 by Tanner Helland
'Created: 22/May/05
'Last updated: 4/May/07
'Last update: MRU entries are kept in the INI file, not the registry.
'
'Handles the creation and maintenance of the program's MRU list.  Originally
' this stored our MRU information in the registry, but I have rewritten the
' entire thing to use only the INI file. PhotoDemon doesn't touch the registry!
'
'***************************************************************************

Option Explicit

'MRUlist will contain string entries of all the most recently used files
Private MRUlist() As String

'Current number of entries in the MRU list
Private numEntries As Long

'Number of recent files to be tracked
Public Const RECENT_FILE_COUNT As Long = 9

'Return the MRU entry at a specific location (used to load MRU files)
Public Function getSpecificMRU(ByVal mIndex As Long) As String

    If (mIndex <= numEntries) And (mIndex >= 0) Then
        getSpecificMRU = MRUlist(mIndex)
    Else
        getSpecificMRU = ""
    End If

End Function

'Load the MRU list from the program's INI file
Public Sub MRU_LoadFromINI()

    'Get the number of MRU entries from the INI file
    numEntries = userPreferences.GetPreference_Long("MRU", "NumberOfEntries", RECENT_FILE_COUNT)
    
    'Only load entries if MRU data exists
    If numEntries > 0 Then
        ReDim MRUlist(0 To numEntries) As String
        For x = 0 To numEntries - 1
            MRUlist(x) = userPreferences.GetPreference_String("MRU", "f" & x, "")
            If x <> 0 Then
                Load FormMain.mnuRecDocs(x)
            Else
                FormMain.mnuRecDocs(x).Enabled = True
            End If
            FormMain.mnuRecDocs(x).Caption = MRUlist(x) & vbTab & "Ctrl+" & x
        Next x
        FormMain.MnuRecentSepBar1.Visible = True
        FormMain.MnuClearMRU.Visible = True
    Else
        FormMain.mnuRecDocs(0).Caption = "Empty"
        FormMain.mnuRecDocs(0).Enabled = False
        FormMain.MnuRecentSepBar1.Visible = False
        FormMain.MnuClearMRU.Visible = False
    End If
    
End Sub

'Save the current MRU list to file (currently done at program close)
Public Sub MRU_SaveToINI()

    'Save the number of current entries
    userPreferences.SetPreference_Long "MRU", "NumberOfEntries", numEntries
    
    'Only save entries if MRU data exists
    If numEntries <> 0 Then
        For x = 0 To numEntries - 1
            userPreferences.SetPreference_String "MRU", "f" & x, MRUlist(x)
        Next x
    End If
    
End Sub

'Add another file to the MRU list
Public Sub MRU_AddNewFile(ByVal newFile As String)

    'Locators
    Dim alreadyThere As Boolean, curLocation As Long
    alreadyThere = False
    curLocation = -1
    
    'First, check to see if our entry currently exists in the MRU list
    For x = 0 To numEntries - 1
        'If we find this entry in the list, then special measures must be taken
        If MRUlist(x) = newFile Then
            alreadyThere = True
            curLocation = x
            GoTo MRUEntryFound
        End If
    Next x
    
MRUEntryFound:
    
    'File already exists in the MRU list somewhere...
    If alreadyThere = True Then
        If curLocation = 0 Then
            Exit Sub
        Else
            'Move every path before this file DOWN
            For x = curLocation To 1 Step -1
                MRUlist(x) = MRUlist(x - 1)
            Next x
        End If
    
    'File doesn't exist in the MRU list...
    Else

        numEntries = numEntries + 1
        If numEntries > RECENT_FILE_COUNT Then numEntries = RECENT_FILE_COUNT
        
        ReDim Preserve MRUlist(0 To numEntries) As String
    
        If numEntries > 1 Then
            For x = numEntries To 1 Step -1
                MRUlist(x) = MRUlist(x - 1)
            Next x
        End If
    
    End If
    
    MRUlist(0) = newFile
    
    'Redraw the MRU menu based on the current list
    If (FormMain.mnuRecDocs(0).Caption = "Empty") Then
        FormMain.mnuRecDocs(0).Enabled = True
        FormMain.MnuRecentSepBar1.Visible = True
        FormMain.MnuClearMRU.Visible = True
    End If
    FormMain.mnuRecDocs(0).Caption = newFile & vbTab & "Ctrl+0"
    
    If numEntries > 1 Then
        'Unload existing menus...
        For x = FormMain.mnuRecDocs.Count - 1 To 1 Step -1
            Unload FormMain.mnuRecDocs(x)
        Next x
        DoEvents
        'Load new menus...
        For x = 1 To numEntries - 1
            Load FormMain.mnuRecDocs(x)
            FormMain.mnuRecDocs(x).Caption = MRUlist(x) & vbTab & "Ctrl+" & x
        Next x
    End If
    
    'The icons in the MRU sub-menu need to be reset after this action
    ResetMenuIcons

End Sub

'Empty the entire MRU list and clear the menu of all entries
Public Sub MRU_ClearList()
    
    'Delete all menu items
    For x = FormMain.mnuRecDocs.Count - 1 To 1 Step -1
        Unload FormMain.mnuRecDocs(x)
    Next x
    FormMain.mnuRecDocs(0).Caption = "Empty"
    FormMain.mnuRecDocs(0).Enabled = False
    FormMain.MnuRecentSepBar1.Visible = False
    FormMain.MnuClearMRU.Visible = False
    
    'Reset the number of entries in the MRU list
    numEntries = 0
    ReDim MRUlist(0) As String
    
    'Clear all entries in the INI file
    For x = 0 To RECENT_FILE_COUNT - 1
        userPreferences.SetPreference_String "MRU", "f" & x, ""
    Next x
    
    'Tell the INI that no files are left
    userPreferences.SetPreference_Long "MRU", "NumberOfEntries", 0
    
    'The icons in the MRU sub-menu need to be reset after this action
    ResetMenuIcons

End Sub

'Return how many MRU entries are currently in the menu
Public Function MRU_ReturnCount() As Long
    MRU_ReturnCount = numEntries
End Function
