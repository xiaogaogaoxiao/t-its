function [position,velocity] = myPlatoonBlock(controllerType, waypoints, dt, totalTime, numOfVehicles, safeDistance)

    
    t = 1:dt:totalTime; % time instances where the controller gives output

    % mass-spring equivalent parameters
    k = 10; % [N/m]
    m = 5;  % [kg]
    
    E = ones(numOfVehicles);
    if(numOfVehicles==1)
      Lg = E;
    elseif(numOfVehicles>1 && strcmp(controllerType, 'MPC'))
      Lg = 2*eye(numOfVehicles) - diag(diag(E,1),1)- diag(diag(E,-1),-1);
%       Lg = 2*eye(numOfVehicles) - diag(diag(E,1),1)- diag(diag(E,-1),-1) - diag(diag(E,-2),-2) - diag(diag(E,2),2);
    elseif(numOfVehicles>1 && strcmp(controllerType, 'distMPC2'))
      Lg = 2*eye(numOfVehicles) - diag(diag(E,1),1)- diag(diag(E,-1),-1);
    end
    
    position = zeros(numOfVehicles, length(t));
    for k=1:numOfVehicles
      position(k, 1) = waypoints(1,1)-(k-1)*safeDistance;
    end
    velocity = zeros(numOfVehicles, length(t));

   %% controller paramters and initialization
    switch(controllerType)
     case 'PID'
    % State matrices and vectors
        Asingle1 = [0 1 ; 0 0];
        Asingle2 = [0 0 ; -k/m 0];
        Bsingle = [0; 1/m];
        Csingle = [1 0];
        A = kron(eye(numOfVehicles), Asingle1) + kron(Lg, Asingle2);
        B = kron(Lg, Bsingle);
%         C = kron(Lg, Csingle);       
        % PID parameters
        Kp = 10; Ki = 1; Kd = 5; % parameters to be tuned
        Xopt = waypoints; % 1D points that the leading vehicle has to follow
        err = zeros(numOfVehicles, length(t));
        X  = zeros(size(A, 1), length(t));
        X(1:2:end,1:2) = position(:,1:2);
        u = zeros(numOfVehicles, length(t));
        Xdd  = zeros(size(A, 1), length(t));

     case 'MPC'
        Asingle1 = [0 1 ; 0 0];
        Asingle2 = [0 0 ; -k/m 0];
        Bsingle = [0; 1/m];
        A = kron(eye(numOfVehicles), Asingle1) + kron(Lg, Asingle2);
        
        B = kron(Lg, Bsingle);        
        Csingle = [1 0];
        C = kron(Lg, Csingle);       
        
        % MPC parameters
        Np = 10;
        Nc = 5; %Nc <= Np
        o = zeros(numOfVehicles, size(A,1));
        Ampc = [A o' ; C*A eye(numOfVehicles)];
        Bmpc = [B ; C*B];
        Cmpc = [o eye(numOfVehicles)];
        Xopt =  zeros(Np*size(A, 1), length(t));
        X  = zeros(size(Ampc, 1), length(t));
        DX  = zeros(size(Ampc, 1), length(t));
%         DU_cvx  = zeros(size(Ampc, 1), length(t));

        F = []; Phi = [];
        for i=1:Np
          F = [F ; Cmpc*Ampc^i];
          phi = [];
          for j=1:Nc
              if(j<=i)
                phi = [phi  Cmpc*Ampc^(i-j)*Bmpc];
              else
                phi = [phi zeros(numOfVehicles, size(B, 2))];
              end
          end
          Phi = [Phi ; phi];
        end
        
     case 'distMPC'
        Asingle = [0 1 ; -k/m 0];
        Bsingle = [0; 1/m];
        Csingle = [1 0];
 
        % MPC parameters
        Np = 10;
        Nc = 5; %Nc <= Np
        o = zeros(1, size(Asingle,1));
        Ampc = [Asingle o' ; Csingle*Asingle 1];
        Bmpc = [Bsingle ; Csingle*Bsingle];
        Cmpc = [o 1];
        
        X  = zeros(size(Ampc, 1), length(t), numOfVehicles);
        DX  = zeros(size(Ampc, 1), length(t), numOfVehicles);

        F = []; Phi = [];
        for i=1:Np
          F = [F ; Cmpc*Ampc^i];
          phi = [];
          for j=1:Nc
              if(j<=i)
                phi = [phi  Cmpc*Ampc^(i-j)*Bmpc];
              else
                phi = [phi zeros(1, size(Bsingle, 2))];
              end
          end
          Phi = [Phi ; phi];
        end

     case 'distMPC2'
        Asingle = [0 1 ; -k/m 0];
        Bsingle = [0; 1/m];
        Csingle = [1 0];
 
        % MPC parameters
        Np = 10;
        Nc = 5; %Nc <= Np
        o = zeros(1, size(Asingle,1));
        Ampc = [Asingle o' ; Csingle*Asingle 1];
        Bmpc = [Bsingle ; Csingle*Bsingle];
        Cmpc = [o 1];
        
        X  = zeros(size(Ampc, 1)*numOfVehicles, length(t));
        DX  = zeros(size(Ampc, 1)*numOfVehicles, length(t));

        Fsingle = []; Phi_single = [];
        for i=1:Np
          Fsingle = [Fsingle ; Cmpc*Ampc^i];
          phi = [];
          for j=1:Nc
              if(j<=i)
                phi = [phi  Cmpc*Ampc^(i-j)*Bmpc];
              else
                phi = [phi zeros(1, size(Bsingle, 2))];
              end
          end
          Phi_single = [Phi_single ; phi];
        end
        
        F = kron(Lg, Fsingle);
        Phi = kron(Lg, Phi_single);
    end

    %% Runtime
    for indx = 3:length(t)-1
        indx
           % controller
           switch(controllerType)
             case 'PID'
               for k=1:numOfVehicles
                 if(k==1)
                  err(k, indx) = Xopt(indx) - X(1, indx); % error computation
                 else
                  err(k, indx) = X(2*k-3, indx) - X(2*k-1, indx) - (k-1)*safeDistance;
                 end
               end
               u(1:numOfVehicles, indx) = Kp*err(1:numOfVehicles, indx) + Ki*sum(err(1:numOfVehicles, 1:indx), 2)*dt + Kd*(err(1:numOfVehicles, indx)-err(1:numOfVehicles, indx-1))/dt;  % PID    
                
               % plant state-space model
               Xdd(:, indx) = A*X(:, indx)+B*u(:, indx);
           
               % plant output (double integrator)
               X(2:2:end, indx+1) = Xdd(1:2:end, indx) + Xdd(2:2:end, indx)*dt;     % get velocity via integration of accel
               X(1:2:end, indx+1) = X(1:2:end, indx) + Xdd(1:2:end, indx)*dt;          % get position via integration of vel
                 
               position(:, indx) = X(1:2:end, indx+1);
               velocity(:, indx) = X(2:2:end, indx+1);
           
             case 'MPC'

               for k=1:numOfVehicles
                   if(k==1)
                     rs(k,1) = (waypoints(indx)-waypoints(indx-1));
                   else
                     rs(k,1) = (position(k-1, indx-1) - position(k-1, indx-2));
                   end
               end
               Rs = kron(ones(Np,1), rs);

               Psi = (Phi'*Phi + 1e-3*eye(Nc*numOfVehicles));
               beta = (Phi'*(Rs - F*DX(:, indx-1)));
%                DU(:, indx) = Psi\beta;
 
               cvx_begin quiet
                    variable DU_cvx(Nc*numOfVehicles)
                    minimize norm(beta-Psi*DU_cvx)
                    subject to
                                        
                    DXX = Ampc*DX(:, indx-1) + Bmpc*DU_cvx(1:numOfVehicles);
                    for k=1:numOfVehicles
                      abs(X(2*k, indx) + DXX(2*k))/dt <=10;
                    end
                    
               cvx_end

               DX(:, indx) = Ampc*DX(:, indx-1) + Bmpc*DU_cvx(1:numOfVehicles);
               X(:, indx+1) = X(:, indx) + DX(:, indx);
               % plant state-space model
               
               position(:, indx) = position(:, indx-1)  + X([2:2:2*numOfVehicles], indx+1);
               velocity(:, indx) = X([2:2:2*numOfVehicles], indx)/dt;
               
            case 'distMPC'

              for k=1:numOfVehicles
               if(k==1)
                 rs(k,1) = (waypoints(indx)-waypoints(indx-1));
               else
                 rs(k,1) = (position(k-1, indx-1) - position(k-1, indx-2));
               end
               Rs = kron(ones(Np,1), rs(k));

               
               Psi = (Phi'*Phi + 1e-3*eye(Nc));
               beta = (Phi'*(Rs - F*DX(:, indx-1, k)));
%                DU(:, indx, k) = Psi\beta;
               cvx_begin quiet
                variable DU_cvx(Nc)
                minimize norm(beta-Psi*DU_cvx)
                subject to

                XX = Ampc*DX(:, indx-1,k) + Bmpc*DU_cvx(1);
                XX/dt >=-100;
                XX/dt <=100;
               cvx_end

               DU(:, indx) = DU_cvx;

               % plant state-space model
               DX(:, indx, k) = Ampc*DX(:, indx-1, k) + Bmpc*DU(1, indx, k);
               
               X(:, indx+1, k) = X(:, indx, k) + DX(:, indx, k);
               position(k, indx) = position(k, indx-1)  + X(1, indx+1, k);
               velocity(k, indx) = X(2, indx, k)/dt;
              end
              
              
            case 'distMPC2'
              
               Rs = [];
               for k=1:numOfVehicles
                   if(k==1)
                     rs(k,1) = (waypoints(indx)-waypoints(indx-1));
                   else
                     rs(k,1) = (position(k-1, indx-1) - position(k-1, indx-2));
                   end
                   Rs = [Rs ; kron(ones(Np,1), rs(k,1))];
               end
               
               Psi = (Phi'*Phi + 1e-3*eye(Nc*numOfVehicles));
               beta = (Phi'*(Rs - F*DX(:, indx-1)));

               % plant state-space model
               for k=1:numOfVehicles



               cvx_begin quiet
                variable DU_cvx(Nc*numOfVehicles)
                minimize norm(beta-Psi*DU_cvx)
                subject to
               
                DXX = Ampc*DX((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx-1) + Bmpc*DU_cvx((k-1)*Nc+1);
                abs(X(2*k, indx) + DXX(2*k))/dt <= 10;
               cvx_end
               
                DX((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx) = Ampc*DX((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx-1) + Bmpc*DU_cvx((k-1)*Nc+1);
                X((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx+1) = X((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx) + DX((k-1)*size(Ampc,2)+1:k*size(Ampc,2), indx);

                position(k, indx) = position(k, indx-1)  + X(2*k, indx+1);
                velocity(k, indx) = X(2*k, indx)/dt;
                
               end
           end
    end
    
    position(:, indx+1) = position(:, indx);
    velocity(:, indx+1) = velocity(:, indx);

end
