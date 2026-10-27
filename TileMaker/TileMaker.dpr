{ @abstract(TileMaker: cuts a large image into a tile set, square tiles at
  several levels of detail, for programs such as GDEMFetch to draw.)

  File > Open reads an image; the window shows its prime factors, the
  levels of detail they allow and the tile sizes that cut every level
  exactly; File > Save As writes the tile set to a new folder with a
  @code(tileset.json) describing it.

  Units:
  @unorderedList(
    @item(@link(TileMakerForm) is the main window.)
    @item(@link(GDEMTiler) reads the image, plans the tile set and writes
      it.)
    @item(@link(GDEMFactors), @link(GDEMResample) and @link(GDEMTileSet),
      in the repository's @code(common) folder, are shared with other
      programs: the prime factors and level planning, the Lanczos
      resampling, and the tile set description.)
  ) }
program TileMaker;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  TileMakerForm in 'ui\TileMakerForm.pas' {frmTileMaker},
  GDEMTiler in 'lib\GDEMTiler.pas',
  GDEMFactors in '..\common\GDEMFactors.pas',
  GDEMResample in '..\common\GDEMResample.pas',
  GDEMTileSet in '..\common\GDEMTileSet.pas';

{$R *.res}

begin
  // Skia draws the window, and decodes and encodes the images
  GlobalUseSkia := True;
  Application.Initialize;
  Application.CreateForm(TfrmTileMaker, frmTileMaker);
  Application.Run;
end.
