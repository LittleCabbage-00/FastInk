@{
  ProductName = 'FastInk'
  ExecutableName = 'FastInk.exe'
  PortableMarkerName = '.fastink-portable'

  # Packaging tool versions are maintained in one place.
  InnoSetup = @{
    Version = '6.7.3'
    DownloadUrl = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe'
    PublisherPattern = 'Pyrsys B.V.'
    ChineseLanguage = @{
      FileName = 'ChineseSimplified.isl'
      Url = 'https://raw.githubusercontent.com/jrsoftware/issrc/1ae7bf81dc0d2013235dfe4bb0b6f4e4a0b6b25c/Files/Languages/ChineseSimplified.isl'
      Sha256 = 'e0b0b350e2245f3c5e65586dfe43d574f6e7f06f2261149aba284954b3fc9a8d'
    }
  }
}
