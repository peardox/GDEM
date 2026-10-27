{ @abstract(Cancellation shared between the user interface and background
  work.)

  The main window creates a @link(TCancelToken) for each background job and
  hands it to the code doing the work. The Cancel button calls
  @link(TCancelToken.Cancel); the work calls @link(TCancelToken.Check) at
  safe points and stops by raising @link(EOperationCancelled). }
unit GDEMCancel;

interface

uses
  System.SysUtils;

type
  { @abstract(Raised when work stops because it was cancelled.)

    Catch this to tell a cancellation apart from a real failure: it should
    be logged, not reported as an error. }
  EOperationCancelled = class(Exception);

  { @abstract(A flag that one thread sets and another checks.)

    Setting and reading a Boolean is atomic on every supported platform, so
    no lock is needed. }
  TCancelToken = class
  private
    { Backing field for @link(Cancelled). }
    FCancelled: Boolean;
  public
    { Asks the work to stop. Safe to call from any thread, more than once. }
    procedure Cancel;

    { Raises @link(EOperationCancelled) if @link(Cancel) has been called. }
    procedure Check;

    { @true once @link(Cancel) has been called. }
    property Cancelled: Boolean read FCancelled;
  end;

implementation

{ TCancelToken }

procedure TCancelToken.Cancel;
begin
  FCancelled := True;
end;

procedure TCancelToken.Check;
begin
  if FCancelled then
    raise EOperationCancelled.Create('Cancelled.');
end;

end.
