classdef BscPmGauss < ott.BscPointmatch
%BscPmGauss provides HG, LG and IG beams using point matching method
%
% BscPmGauss properties:
%   type                Type of beam ('gaussian', 'lg', 'hg', or 'ig')
%   mode                Beam modes (2 or 4 element vector)
%   polarisation        Beam polarisation
%   truncation_angle    Truncation angle for beam
%   beam_offset         Offset for original beam calculation
%   waist0              Beam waist at focal plane
%
% BscPmGauss methods:
%
% This class is based on bsc_pointmatch_farfield.m and
% bsc_pointmatch_focalplane.m from ottv1.
%
% This file is part of the optical tweezers toolbox.
% See LICENSE.md for information about using/distributing this file.

  properties (SetAccess=protected)
    type               % Type of beam ('gaussian', 'lg', 'hg', or 'ig')
    mode               % Beam modes (2 or 4 element vector)
    polarisation       % Beam polarisation
    truncation_angle   % Truncation angle for beam
    beam_offset        % Offset for original beam calculation
    waist0             % Beam waist at focal plane
  end

  % TODO: Generalize BscPointmatch for farfield and focal plane
  % TODO: Incorperate bsc_pointmatch_focalplane option for gaussian beams.

  methods
    function beam = BscPmGauss(varargin)
      %BSCPMGAUSS construct a new IG, HG or LG gaussian beam.
      %
      % BSCPMGAUSS() constructs a new Gassian beam (LG00).
      %
      % BSCPMGAUSS(type, mode) constructs a new beam with the given type.
      % Supported types [mode]:
      %     'lg'    Laguarre-Gauss  [ radial azimuthal ]
      %     'hg'    Hermite-Gauss   [ m n ]
      %     'ig'    Ince-Gauss      [ paraxial azimuthal parity elipticity ]
      %
      % BSCPMGAUSS(..., 'Nmax') specifies the desired Nmax for the beam.
      % If omitted, Nmax is estimated using ka2nmax(k_medium*waist0).
      %
      % TODO: Documentation

      beam = beam@ott.BscPointmatch(varargin{:});
      beam.type = 'incomming';

      % Parse inputs
      p = inputParser;
      p.addOptional('type', 'lg');
      p.addOptional('mode', [ 0 0 ]);

      p.addParameter('Nmax', []);
      p.addParameter('offset', []);
      p.addParameter('polarisation', [ 1 1i ]);

      p.addParameter('NA', []);
      p.addParameter('angle_deg', []);
      p.addParameter('angle', []);

      p.addParameter('truncation_angle_deg', []);
      p.addParameter('truncation_angle', []);

      p.parse(varargin{:});

      % TODO: bsc_pointmatch_farfield.m had other arguments
      % optional parameters:
      %
      % 'radial' - makes radial component with weighting xcomponent.
      % 'azimuthal' - makes azimuthal component with weighting ycomponent.
      % (note: azimuthal and radial components are not mutually exclusive.)
      % 'sintheta' - angular scaling function is the same as the one present in
      %   standard microscope objectives. Preserves high order mode shape!
      % 'tantheta' - default angular scaling function, "small angle
      %   approximation" which is valid for thin lenses ONLY. Does not preserve
      %   high order mode shape at large angles.

      import ott.*
      import utils.*

      axisymmetry = 1;

      zero_rejection_level = 1e-8;

      medium_refractive_index = 1;
      beam_wavelength0 = 1;

      ott.warning('internal');

      %radial and azimuthal polarisation.
      radial=0;
      azimuthal=0;

      %% mode selection
      switch p.Results.type
        case 'hg'
          m = p.Results.mode(1);
          n = p.Results.mode(2);
          paraxial_order=n+m;
          [modeweights,initial_mode,final_mode] = ...
              paraxial_transformation_matrix(paraxial_order,0,1,0);
          [row]=find(final_mode(:,1)==m,1);
        case 'lg'
          radial_mode = p.Results.mode(1);
          azimuthal_mode = p.Results.mode(2);
          paraxial_order=2*radial_mode+abs(azimuthal_mode);
          modeweights=eye(paraxial_order+1);
          row=(azimuthal_mode+paraxial_order)/2+1;
          
          i2_out=[-paraxial_order:2:paraxial_order].';
          i1_out=floor((paraxial_order-abs(i2_out))/2);
          
          initial_mode=[i1_out,i2_out];
        case 'ig'
          paraxial_order = p.Results.mode(1);
          azimuthal_mode = p.Results.mode(2);
          parity = p.Results.mode(3);
          elipticity = p.Results.mode(4);
          
          [modeweights,initial_mode,final_mode] = ...
             paraxial_transformation_matrix(paraxial_order,0,[2,elipticity],0);
          
          [row]=find(and(final_mode(:,2)==azimuthal_mode, ...
              final_mode(:,3)==parity),1);
          
          if and(paraxial_order>1,isempty(row))
            ott.warning('external');
            error('Observe parity convensions!')
          end
      end
      % find the mode columns:
      keepz=(abs(modeweights(row,:))>0);
      initial_mode=initial_mode(keepz,:);
      c=modeweights(row,keepz);

      beam_angle_specified = isempty(p.Results.angle) ...
          + isempty(p.Results.angle_deg) + isempty(p.Results.NA);

      % Find beam_angle_deg
      if beam_angle_specified > 1
        ott.warning('external');
        error('Too many inputs.  Only specify NA, angle or angle_deg');
      elseif isempty(p.Results.angle) && isempty(p.Results.angle_deg)
        if isempty(p.Results.NA)
          NA = 1.02;
        else
          NA = p.Results.NA;
        end
        beam_angle_deg = asin(NA/medium_refractive_index)*180.0/pi;
      elseif ~isempty(p.Results.angle_deg)
        beam_angle_deg = p.Results.angle_deg;
      elseif ~isempty(p.Results.angle)
        beam_angle_deg = p.Results.angle*180/pi;
      end

      k = 2*pi * medium_refractive_index / beam_wavelength0;

      [xcomponent, ycomponent] = p.Results.polarisation;
      truncation_angle = p.Results.truncation_angle_deg;
      offset = p.Results.offset;

      if numel(offset) == 3 && any(abs(offset(1:2))>0)
        ott.warning('external');
        ott.warning('ott:bsc_pointmatch_farfield:offsets', ...
            ['Beam offsets with x and y components cannot be ' ...
             'axi-symmetric, beam symmetry is now off, and the ' ...
             'calculation will be much slower. It is highly recommended ' ...
             'that a combination of rotations and translations are ' ...
             'used on BSCs instead.']);
          ott.warning('internal');
          axisymmetry=0;
      end

      aperture_function=0;

      % Grid of points over sphere
      ntheta = (nmax + 1);
      nphi = 2*(nmax + 1);
      if axisymmetry
          ntheta = 2*(nmax+1);
          nphi = 3;
          if ~strcmp(beam_type, 'lg')
              nphi = paraxial_order+3-rem(paraxial_order,2);
          end
      end

      [theta,phi] = angulargrid(ntheta,nphi);

      np = length(theta);

      % Find electric field at all points
      % In the far-field, we have:
      % w = 2|z|/(k w0)     (cylindrical coords)
      % r/w = kr w0 / 2 |z| (cylindrical coords)
      % r = z tan(theta)    (cylindrical -> spherical conversion)
      % r/w = k w0 |tan(theta)|/2 (spherical)

      %central_irradiance = 2*beam_power / (pi*w0^2);
      %central_amplitude = sqrt(2*central_irradiance / ...
      %   (speed_in_medium*kappa));

      central_amplitude = 1;
      w0 = paraxial_beam_waist(paraxial_order);
      wscaling=1/tan(abs(beam_angle_deg/180*pi));
      rw = 2*(wscaling * w0)^2 * tan(theta).^2 ;
      dr = (wscaling * w0) * (sec(theta)).^2 ;

      if aperture_function==2

        wscaling=1/sin(abs(beam_angle/180*pi));

        rw = 2*(wscaling * w0)^2 * sin(theta).^2 ;
        dr = (wscaling * w0) * abs(cos(theta)) ;
      end

      % degree and order of all modes
      total_modes = nmax^2 + 2*nmax;
      [nn,mm] = combined_index((1:total_modes)');

      mode_index_vector=[];
      beam_envelope = zeros(np,length(c));
      for ii=1:length(c)
          radial_mode=initial_mode(ii,1);
          azimuthal_mode=initial_mode(ii,2);
          
          norm_paraxial=sqrt(2*factorial(radial_mode)/(pi*factorial(radial_mode+abs(azimuthal_mode))));
          L = laguerre(radial_mode,abs(azimuthal_mode),rw);
          beam_envelope(:,ii) = norm_paraxial.*rw.^abs(azimuthal_mode/2) .* L .* exp(-rw/2 + 1i*azimuthal_mode*phi+1i*pi/2*(radial_mode*2+abs(azimuthal_mode)+1));
          mode_input_power=sqrt(sum(2*pi*abs(beam_envelope(:,ii)).^2.*sqrt(rw/2).*abs(dr)));
          aperture_power_normalization=sqrt(sum(2*pi*abs(beam_envelope(:,ii)).^2.*sin(theta)));
          
          beam_envelope(:,ii)=c(ii)*beam_envelope(:,ii)/aperture_power_normalization*mode_input_power;
          
          mode_index_vector=[mode_index_vector;find(mm==azimuthal_mode+1-max([azimuthal,radial])|mm==azimuthal_mode-1+max([azimuthal,radial]))];

      end
      mode_index_vector=unique(mode_index_vector);

      beam_envelope=sum(beam_envelope,2);
      outbeam = find(theta<pi*(180-truncation_angle)/180);
      beam_envelope(outbeam) = 0;

      if ~isempty(offset)
        rhat = rtpv2xyzv( ones(size(theta)), zeros(size(theta)), ...
            zeros(size(theta)), ones(size(theta)), theta, phi );
        [offset,rhat] = matchsize(offset,rhat);
        phase_shift = exp( -1i * k * dot(offset,rhat,2) );
        beam_envelope = beam_envelope .* phase_shift;
      end
      Ex = xcomponent * beam_envelope * central_amplitude;
      Ey = ycomponent * beam_envelope * central_amplitude;

      if any(azimuthal|radial)
        Etheta=-radial*xcomponent*beam_envelope * central_amplitude;
        Ephi=azimuthal*ycomponent*beam_envelope * central_amplitude;
      else
        Etheta = - Ex .* cos(phi) - Ey .* sin(phi);
        Ephi = - Ex .* sin(phi) + Ey .* cos(phi);
      end

      e_field = [[ Etheta(:); Ephi(:) ]];

      if axisymmetry
        nn=nn(mode_index_vector);
        mm=mm(mode_index_vector);
        
        removeels=find(abs(mm)>paraxial_order+1);
        nn(removeels)=[];
        mm(removeels)=[];
      end

      coefficient_matrix = zeros(2*np,2*length(nn));

      for n = 1:max(nn)
        ci=find(nn==n);
        
        [~,dtY,dpY]= spharm(n,mm(ci),theta,phi);
        
        coefficient_matrix(:,ci) = [dpY;-dtY] * 1i^(n+1)/sqrt(n*(n+1));
        coefficient_matrix(:,ci+length(nn)) = [dtY;dpY] * 1i^(n)/sqrt(n*(n+1));
      end

      a=zeros(size(nn));
      b=zeros(size(nn));

      expansion_coefficients = coefficient_matrix \ e_field;
      %fprintf(1,'done!\n');
      %toc
      a = expansion_coefficients(1:end/2,:);
      b = expansion_coefficients(1+end/2:end,:);

      p=abs(a).^2+abs(b).^2;
      binaryvector=(p>zero_rejection_level*max(p));

      nn=nn(binaryvector);
      mm=mm(binaryvector);
      a=a(binaryvector);
      b=b(binaryvector);

      % Make the beam vector and store the coefficients
      [beam.a, beam.b] = beam.make_beam_vector(a, b, nn, mm);

      ott.warning('external');
    end
  end
end

