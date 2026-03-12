import enum
from sqlalchemy import Column, Integer, String, Boolean, Enum
from database import Base


class VehicleType(enum.Enum):
    car = "car"
    motorcycle = "motorcycle"
    ev = "ev"
    truck = "truck"
    bus = "bus"


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)

    # Vehicle profile — affects parking rule evaluation
    vehicle_type = Column(Enum(VehicleType), default=VehicleType.car, nullable=False)
    is_disabled = Column(Boolean, default=False)        # has disability parking permit
    has_resident_permit = Column(Boolean, default=False)
    resident_zone = Column(String, default="")          # e.g. "A", "B4", "Östermalm"
